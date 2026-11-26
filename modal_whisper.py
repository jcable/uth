"""
Modal server for a fine-tuned Whisper large-v3 turbo model in CTranslate2
format, run with faster-whisper.

Setup (once):
    pip install modal
    modal setup
    modal secret create whisper-secrets API_TOKEN=<long-random-string> HF_TOKEN=<hf-token-if-model-is-private>

Deploy:
    modal deploy modal_whisper.py

Modal prints the base URL (…-transcriber-web.modal.run). The app POSTs raw
audio bytes to <base URL>/transcribe with the header
    Authorization: Bearer <API_TOKEN>
and gets back {"text": "..."}.
"""
import io
import os
import json
import time
import modal
import asyncio

# ---- CHANGE THIS to your CTranslate2 model's Hugging Face repo id ----
MODEL_ID = "eist-edinburgh/whisper-large-v3-turbo-gaelic-ct2-v2"

# Set to e.g. "en" to force a language, or None to auto-detect.
LANGUAGE = None

# Browser origins allowed to call the API (CORS). Native mobile apps ignore
# this. Replace "*" with your deployed site's origin(s) before going public.
ALLOWED_ORIGINS = ["*"]

app = modal.App("uth-transcribe")

# ctranslate2 (used by faster-whisper) needs CUDA 12 cuBLAS and cuDNN 9.
# Installing them with pip requires LD_LIBRARY_PATH to point at them before
# Python starts, which is what the .env() below does.
SITE = "/usr/local/lib/python3.11/site-packages"

image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(
        "faster-whisper",
        "nvidia-cublas-cu12",
        "nvidia-cudnn-cu12==9.*",
        "huggingface_hub",
        "fastapi[standard]",
        "firebase-admin",
    )
    .env(
        {
            "HF_HOME": "/cache",
            "LD_LIBRARY_PATH": f"{SITE}/nvidia/cudnn/lib:{SITE}/nvidia/cublas/lib",
        }
    )
)
# faster-whisper decodes audio with PyAV (FFmpeg is bundled), so no apt ffmpeg needed.

# These imports only run inside the Modal container, so they don't need to be
# installed on your own machine.
with image.imports():
    from fastapi import FastAPI, HTTPException, Request
    from fastapi.middleware.cors import CORSMiddleware
    from faster_whisper import WhisperModel

# Persistent volume so model weights are downloaded once, not on every cold start.
cache = modal.Volume.from_name("whisper-hf-cache", create_if_missing=True)
#secrets = modal.Secret.from_name("whisper-secrets")
# Modal Secret named "firebase-admin" containing:
#   FIREBASE_SERVICE_ACCOUNT_JSON = <contents of the service account key JSON>
# Create it with:
#   modal secret create firebase-admin FIREBASE_SERVICE_ACCOUNT_JSON="$(cat key.json)"
secrets = [modal.Secret.from_name("firebase-admin")]
# TODO Merge secrets?

# Simple shared counter store for per-user rate limiting
rate_limits = modal.Dict.from_name("rate-limits", create_if_missing=True)

RATE_LIMIT = int(os.environ.get('RATE_LIMIT', 30))        # requests
RATE_WINDOW = int(os.environ.get('RATE_WINDOW', 60))      # per this many seconds

def _init_firebase():
    import firebase_admin
    from firebase_admin import credentials

    if not firebase_admin._apps:
        info = json.loads(os.environ["FIREBASE_SERVICE_ACCOUNT_JSON"])
        firebase_admin.initialize_app(credentials.Certificate(info))

async def _check_rate_limit(uid: str):
    window = int(time.time() // RATE_WINDOW)
    key = f"{uid}:{window}"
    count = await rate_limits.get.aio(key, 0) + 1  # not atomic; fine for a sketch
    await rate_limits.put.aio(key, count)
    if count > RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Too many requests")

async def _authorise(request):
    from firebase_admin import app_check, auth

    _init_firebase()

    authorization = request.headers.get("authorization", "")
    x_firebase_appcheck = request.headers.get("X-Firebase-AppCheck", "")

    # 1. Verify the user's Firebase ID token
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    try:
        decoded = auth.verify_id_token(authorization.removeprefix("Bearer "))
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")
    uid = decoded["uid"]

    if os.environ.get('DISABLE_APPCHECK', '0') != '1':
        # 2. Verify App Check (proves the request came from your genuine app)
        if not x_firebase_appcheck:
            raise HTTPException(status_code=401, detail="Missing App Check token")
        try:
            app_check.verify_token(x_firebase_appcheck)
        except Exception:
            raise HTTPException(status_code=401, detail="Invalid App Check token")

    # 3. Rate limit per user
    await _check_rate_limit(uid)
              
@app.cls(
    image=image,
    gpu="T4",  # 16 GB is plenty for the turbo model in fp16; try "L4" for more speed
    volumes={"/cache": cache},
    secrets=secrets,
    scaledown_window=120,  # keep the container warm 2 min after the last request
    timeout=300,
)
class Transcriber:
    @modal.enter()
    def load(self):
        # Accepts a Hugging Face repo id (downloaded on first run, then cached
        # in the volume). HF_TOKEN from the secret is picked up automatically
        # for private repos.
        self.model = WhisperModel(MODEL_ID, device="cuda", compute_type="float16")
        cache.commit()  # persist downloaded weights for future cold starts

    # A full FastAPI app (instead of a bare endpoint) so we can answer the
    # browser's CORS preflight (OPTIONS) request. Without this, web builds of
    # the app are blocked by the browser even though the server is working.
    @modal.asgi_app()
    def web(self):
        api = FastAPI()
        api.add_middleware(
            CORSMiddleware,
            # "*" is fine for testing. For production, list your site's origin,
            # e.g. ["https://your-app.example.com"].
            allow_origins=ALLOWED_ORIGINS,
            allow_methods=["POST", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type"],
        )

        @api.get("/capacity")
        async def capacity(request: Request):

            _authorise(request)

            s = await modal.Workspace.from_context().billing.summary()

            return({'metered_cost': float(s['metered_cost']), 'billed_cost':  float(s['billed_cost']), 'allowance': float(os.environ.get('ALLOWANCE', 30.0)) });

        @api.post("/transcribe")
        async def transcribe(request: Request):

            _authorise(request)

            audio_bytes = await request.body()
            if not audio_bytes:
                raise HTTPException(status_code=400, detail="Empty request body")
            if len(audio_bytes) > 25 * 1024 * 1024:
                raise HTTPException(
                    status_code=413, detail="Audio too large (max 25 MB)"
                )

            segments, _info = self.model.transcribe(
                io.BytesIO(audio_bytes),
                beam_size=5,
                language=LANGUAGE,
                vad_filter=True,  # skips silence; also handles recordings > 30 s
            )
            # `segments` is a generator: transcription runs while iterating.
            text = " ".join(s.text.strip() for s in segments).strip()
            return {"text": text}

        return api

"""
Modal server for a fine-tuned Whisper large-v3 turbo model in CTranslate2
format, run with faster-whisper.

Setup (once):
    pip install modal
    modal setup
    modal secret create whisper-secrets API_TOKEN=<long-random-string> HF_TOKEN=<hf-token-if-model-is-private>

Deploy:
    modal deploy modal_whisper.py

Modal prints the endpoint URL. The app POSTs raw audio bytes to it with the
header:  Authorization: Bearer <API_TOKEN>   and gets back {"text": "..."}.
"""
import io
import os

import modal

MODEL_ID = "eist-edinburgh/whisper-large-v3-turbo-gaelic-ct2-v2"

# Set to e.g. "en" to force a language, or None to auto-detect.
LANGUAGE = None

app = modal.App("whisper-transcribe")

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
    from fastapi import HTTPException, Request
    from faster_whisper import WhisperModel

# Persistent volume so model weights are downloaded once, not on every cold start.
cache = modal.Volume.from_name("whisper-hf-cache", create_if_missing=True)
secrets = modal.Secret.from_name("whisper-secrets")


@app.cls(
    image=image,
    gpu="T4",  # 16 GB is plenty for the turbo model in fp16; try "L4" for more speed
    volumes={"/cache": cache},
    secrets=[secrets],
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

    @modal.fastapi_endpoint(method="POST")
    async def transcribe(self, request: Request):
        expected = os.environ.get("API_TOKEN")
        auth = request.headers.get("authorization", "")
        if not expected or auth != f"Bearer {expected}":
            raise HTTPException(status_code=401, detail="Unauthorized")

        audio_bytes = await request.body()
        if not audio_bytes:
            raise HTTPException(status_code=400, detail="Empty request body")
        if len(audio_bytes) > 25 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="Audio too large (max 25 MB)")

        segments, _info = self.model.transcribe(
            io.BytesIO(audio_bytes),
            beam_size=5,
            language=LANGUAGE,
            vad_filter=True,  # skips silence; also handles recordings > 30 s
        )
        # `segments` is a generator: transcription actually runs while iterating.
        text = " ".join(segment.text.strip() for segment in segments).strip()
        return {"text": text}

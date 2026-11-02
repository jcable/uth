"""
Modal server for a fine-tuned Whisper large-v3 turbo model.

Setup (once):
    pip install modal
    modal setup
    modal secret create whisper-secrets API_TOKEN=<long-random-string> HF_TOKEN=<hf-token-if-model-is-private>

Deploy:
    modal deploy modal_whisper.py

Modal prints the endpoint URL. The Android app POSTs raw audio bytes to it
with the header:  Authorization: Bearer <API_TOKEN>
"""
import os
import modal

# ---- CHANGE THIS to your fine-tuned model's Hugging Face repo id ----
MODEL_ID = "eist-edinburgh/whisper-large-v3-turbo-gaelic-ct2-v2"

app = modal.App("whisper-transcribe")

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg")  # lets the pipeline decode m4a/aac/wav/etc.
    .pip_install(
        "torch",
        "transformers",
        "accelerate",
        "huggingface_hub",
        "fastapi[standard]",
    )
    .env({"HF_HOME": "/cache"})
)

# These imports only run inside the Modal container, so they don't need to be
# installed on your own machine.
with image.imports():
    from fastapi import HTTPException, Request

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
        import torch
        from transformers import pipeline

        token = os.environ.get("HF_TOKEN") or None
        self.pipe = pipeline(
            "automatic-speech-recognition",
            model=MODEL_ID,
            torch_dtype=torch.float16,
            device="cuda:0",
            token=token,
            chunk_length_s=30,  # handles recordings longer than 30 s
        )
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

        result = self.pipe(audio_bytes, return_timestamps=False)
        return {"text": result["text"].strip()}

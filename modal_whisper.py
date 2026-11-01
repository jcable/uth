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
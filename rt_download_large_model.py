import sys
import os

try:
    from faster_whisper import WhisperModel
    print("faster-whisper is installed. Downloading large-v3 model...")
except ImportError:
    print("Error: faster-whisper is not installed in the python environment.")
    print("Please make sure you have installed transcription dependencies first.")
    sys.exit(1)

model_size = "large-v3"
print(f"Downloading model '{model_size}' from Hugging Face once...")
print("This may take several minutes depending on your internet connection...")
try:
    # This will download the model files and save them to the Hugging Face hub cache directory.
    # It prints standard download progress bars from huggingface_hub to sys.stderr.
    model = WhisperModel(
        model_size,
        device="cpu",
        compute_type="int8",
        local_files_only=False
    )
    print("Download completed successfully!")
    print(f"Model '{model_size}' is now cached and ready for offline transcription!")
except Exception as e:
    print(f"Error downloading model: {e}")
    sys.exit(1)

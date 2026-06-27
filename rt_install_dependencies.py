import argparse
import glob
import os
import shutil
import subprocess
import sys


def write_status(path, value):
    temp = path + f".{os.getpid()}.tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write(str(value))
    os.replace(temp, path)


def run(command, log):
    log.write("\n> " + " ".join(command) + "\n")
    log.flush()
    process = subprocess.run(
        command,
        stdout=log,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return process.returncode


def find_ffmpeg():
    direct = shutil.which("ffmpeg")
    if direct:
        return direct
    if sys.platform == "win32":
        root = os.path.join(
            os.environ.get("LOCALAPPDATA", ""),
            "Microsoft", "WinGet", "Packages")
        matches = glob.glob(
            os.path.join(root, "Gyan.FFmpeg*", "**", "ffmpeg.exe"),
            recursive=True)
        if matches:
            return matches[0]
    return None


def pip_install(packages, log, extra_index_url=None):
    cmd = [sys.executable, "-m", "pip", "install", "--user",
           "--disable-pip-version-check"] + packages
    if extra_index_url:
        cmd += ["--extra-index-url", extra_index_url]
    return run(cmd, log)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    with open(args.log, "w", encoding="utf-8") as log:
        code = 0

        # ── 1. faster-whisper (core ASR) ────────────────────────────────────
        try:
            import faster_whisper  # noqa: F401
            log.write("faster-whisper: already installed.\n")
        except ImportError:
            log.write("Installing faster-whisper...\n")
            code = pip_install(["faster-whisper"], log)
            if code != 0:
                run([sys.executable, "-m", "ensurepip", "--upgrade"], log)
                code = pip_install(["faster-whisper"], log)

        # ── 2. whisperx (forced alignment) ──────────────────────────────────
        if code == 0:
            try:
                import whisperx  # noqa: F401
                log.write("whisperx: already installed.\n")
            except ImportError:
                log.write("\nInstalling whisperx (forced alignment engine)...\n")
                log.write("This may take a few minutes on first run.\n")
                log.flush()
                # whisperx needs torch; install CPU-only torch first if missing
                try:
                    import torch  # noqa: F401
                    log.write("torch: already installed.\n")
                except ImportError:
                    log.write("Installing PyTorch (CPU)...\n")
                    pip_install(
                        ["torch", "torchaudio", "--index-url",
                         "https://download.pytorch.org/whl/cpu"],
                        log)

                wx_code = pip_install(["whisperx"], log)
                if wx_code != 0:
                    log.write(
                        "\nwhisperx installation failed. "
                        "The transcription will still work using stable-whisper "
                        "(less accurate word timing).\n")
                    # Not a fatal error - stable-whisper still works
                else:
                    log.write("whisperx: installed successfully.\n")

        # ── 3. stable-whisper (fallback / VAD refinement) ───────────────────
        if code == 0:
            try:
                import stable_whisper  # noqa: F401
                log.write("stable-whisper: already installed.\n")
            except ImportError:
                log.write("\nInstalling stable-whisper (fallback)...\n")
                code = pip_install(["stable-whisper"], log)

        # ── 4. FFmpeg (not needed for WAV export, but kept for compatibility) ─
        if code == 0 and not find_ffmpeg():
            if sys.platform == "win32" and shutil.which("winget"):
                log.write("\nFFmpeg is missing; installing through WinGet...\n")
                log.flush()
                code = run([
                    "winget", "install", "--id", "Gyan.FFmpeg", "-e",
                    "--accept-package-agreements",
                    "--accept-source-agreements",
                    "--silent",
                ], log)
            else:
                log.write(
                    "\nFFmpeg is missing. Install FFmpeg manually and add to PATH "
                    "(optional - not required for WAV export).\n")

        if find_ffmpeg():
            log.write(f"\nFFmpeg: {find_ffmpeg()}\n")

        log.write(
            "\nDependency setup completed successfully.\n"
            if code == 0
            else f"\nInstallation failed with exit code {code}.\n")
        log.flush()
    write_status(args.status, code)


if __name__ == "__main__":
    try:
        main()
    except BaseException as error:
        try:
            with open(sys.argv[sys.argv.index("--log") + 1], "a",
                      encoding="utf-8") as log:
                log.write(f"\nFatal setup error: {error}\n")
            write_status(sys.argv[sys.argv.index("--status") + 1], 1)
        except Exception:
            pass
        raise

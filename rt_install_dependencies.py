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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    with open(args.log, "w", encoding="utf-8") as log:
        code = 0
        try:
            import faster_whisper  # noqa: F401
            log.write("faster-whisper is already installed.\n")
        except ImportError:
            command = [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--user",
                "--disable-pip-version-check",
                "faster-whisper",
            ]
            code = run(command, log)
            if code != 0:
                log.write("\npip failed; trying ensurepip...\n")
                log.flush()
                ensure_code = run(
                    [sys.executable, "-m", "ensurepip", "--upgrade"], log)
                if ensure_code == 0:
                    code = run(command, log)
            if code == 0:
                code = run(
                    [sys.executable, "-c", "import faster_whisper"], log)

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
                    "\nFFmpeg is missing and WinGet is unavailable. "
                    "Install FFmpeg manually and add it to PATH.\n")
                code = 1

        if code == 0 and not find_ffmpeg():
            log.write("\nFFmpeg installation finished but ffmpeg.exe was not found.\n")
            code = 1
        elif code == 0:
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

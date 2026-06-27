import argparse
import os
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    with open(args.log, "w", encoding="utf-8") as log:
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
        log.write(
            "\nInstallation completed successfully.\n"
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

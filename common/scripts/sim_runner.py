import subprocess
from pathlib import Path


PROJECT_DIRECTORY = (
    Path(__file__).resolve().parents[2]
    / "01_fifo_verification"
)

STEPS = (
    ("Lint", ["mingw32-make", "lint"]),
    ("Simulation and waveform", ["mingw32-make", "wave"]),
    ("Cleanup", ["mingw32-make", "clean"]),
)


def main():
    if not (PROJECT_DIRECTORY / "makefile").is_file():
        raise FileNotFoundError(
            f"Makefile not found in: {PROJECT_DIRECTORY}"
        )

    for name, command in STEPS:
        print(f"\n=== {name} ===")

        result = subprocess.run(
            command,
            cwd=PROJECT_DIRECTORY,
        )

        print(f"{name} finished with exit code {result.returncode}.")
        input("Press Enter to continue...")


if __name__ == "__main__":
    main()
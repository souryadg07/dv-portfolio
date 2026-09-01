import argparse
from pathlib import Path
import subprocess

import os
from pathlib import Path


def setup_questa_environment():
    questa_bin = Path(r"C:\lscc\radiant\2025.2\questasim\win64")

    if not questa_bin.is_dir():
        raise FileNotFoundError(f"Questa directory not found: {questa_bin}")

    os.environ["PATH"] = f"{questa_bin}{os.pathsep}{os.environ.get('PATH', '')}"


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Compile and run SystemVerilog using Questa."
    )
    parser.add_argument(
        "sources",
        nargs="+",
        type=Path,
        help="SystemVerilog source files in compilation order.",
    )
    parser.add_argument(
        "--top",
        required=True,
        help="Name of the top-level testbench module.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("sim_out"),
        help="Simulation output directory.",
    )
    return parser.parse_args()


def validate_sources(sources):
    validated_sources = []
    supported_extensions = {".v", ".sv", ".vh", ".svh"}
    for source in sources:
        source = source.resolve()
        if not source.is_file():
            raise FileNotFoundError(f"Source file not found: {source}")
        if source.suffix.lower() not in supported_extensions:
            raise ValueError(f"Unsupported source file: {source}")
        validated_sources.append(source)
    return validated_sources

def run_simulation(top_module, output_directory):
    subprocess.run(
        [
            "vsim",
            "-c",
            "-work",
            "work",
            top_module,
            "-do",
            "run -all; quit -code 0",
        ],
        cwd=output_directory,
        check=True,
    )

def compile_design(sources, output_directory):
    work_library = output_directory / "work"

    if not work_library.exists():
        subprocess.run(
            ["vlib", "work"],
            cwd=output_directory,
            check=True,
        )

    subprocess.run(
        ["vlog", "-sv", "-work", "work", *sources],
        cwd=output_directory,
        check=True,
    )

def main():
    args = parse_arguments()

    sources = validate_sources(args.sources)
    output_directory = args.out.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)

    setup_questa_environment()
    compile_design(sources, output_directory)
    run_simulation(args.top, output_directory)

    return 0

if __name__ == "__main__":
    main()
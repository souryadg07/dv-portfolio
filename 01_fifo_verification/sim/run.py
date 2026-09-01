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

def setup_gtkwave_environment():
    gtkwave_bin = Path(r"C:\Users\soury\oss-cad-suite\bin")

    if not (gtkwave_bin / "gtkwave.exe").is_file():
        raise FileNotFoundError(
            f"GTKWave executable not found: {gtkwave_bin}"
        )

    os.environ["PATH"] = (
        f"{gtkwave_bin}{os.pathsep}"
        f"{os.environ.get('PATH', '')}"
    )

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
    parser.add_argument(
        "--wave",
        type=Path,
        default=Path("waves.vcd"),
        help="Path for the generated VCD waveform.",
    )

    parser.add_argument(
        "--gui",
        action="store_true",
        help="Open the generated waveform in GTKWave.",
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

def run_simulation(top_module, output_directory, waveform):
    if not waveform.is_absolute():
        waveform = output_directory / waveform

    waveform = waveform.resolve()
    waveform.parent.mkdir(parents=True, exist_ok=True)

    subprocess.run(
        [
            "vsim",
            "-c",
            "-voptargs=+acc",
            "-work",
            "work",
            top_module,
            f"+wave={waveform.as_posix()}",
            "-do",
            "run -all; quit -code 0",
        ],
        cwd=output_directory,
        check=True,
    )

    return waveform

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


def open_waveform(waveform):
    environment_script = Path(
        r"C:\Users\soury\oss-cad-suite\environment.bat"
    )

    if not environment_script.is_file():
        raise FileNotFoundError(
            f"Environment script not found: {environment_script}"
        )

    command = (
        f"call {environment_script} "
        f"&& start gtkwave {waveform.resolve()}"
    )

    subprocess.Popen(
        ["cmd.exe", "/d", "/c", command],
        cwd=waveform.parent,
    )

def main():
    args = parse_arguments()

    sources = validate_sources(args.sources)
    output_directory = args.out.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)

    setup_questa_environment()
    compile_design(sources, output_directory)
    waveform = run_simulation(
    args.top,
    output_directory,
    args.wave,
    )

    if args.gui:
        setup_gtkwave_environment()
        open_waveform(waveform)

    return 0

if __name__ == "__main__":
    main()
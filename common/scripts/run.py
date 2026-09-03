import argparse
from pathlib import Path
import subprocess

import os
import shutil

# def setup_questa_environment():
#     # questa_bin = Path(r"C:\lscc\radiant\2025.2\questasim\win64")
#     questa_bin = Path(r"C:\altera_lite\25.1std\questa_fse\win64")

#     if not questa_bin.is_dir():
#         raise FileNotFoundError(f"Questa directory not found: {questa_bin}")

#     os.environ["PATH"] = f"{questa_bin}{os.pathsep}{os.environ.get('PATH', '')}"

def setup_questa_environment():
    questa_bin = Path(r"C:\altera_lite\25.1std\questa_fse\win64")

    if not questa_bin.is_dir():
        raise FileNotFoundError(f"Questa directory not found: {questa_bin}")

    os.environ["PATH"] = f"{questa_bin}{os.pathsep}{os.environ.get('PATH', '')}"

    license_file = Path(r"c:\altera_lite\LR-186474_License.dat")
    if license_file.is_file():
        os.environ["SALT_LICENSE_SERVER"] = str(license_file)
        os.environ["LM_LICENSE_FILE"] = str(license_file)

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
    parser.add_argument(
        "--sim",
        choices=("questa", "verilator"),
        default="questa",
        help="Simulator backend.",
    )
    parser.add_argument(
        "--lint",
        action="store_true",
        help="Run Verilator lint only.",
    )

    parser.add_argument(
        "--incdir",
        nargs="*",
        type=Path,
        default=[],
        help="Include directories for `include resolution.",
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

def run_questa(top_module, output_directory, waveform):
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
            "add wave -r /*; log -r /*; run -all; quit -f",
        ],
        cwd=output_directory,
        check=True,
    )

    return output_directory / "vsim.wlf"

def compile_questa(sources, output_directory, incdirs=()):
    work_library = output_directory / "work"

    if not work_library.exists():
        subprocess.run(["vlib", "work"], cwd=output_directory, check=True)

    incdir_args = [f"+incdir+{d.resolve().as_posix()}" for d in incdirs]

    subprocess.run(
        ["vlog", "-sv", "+define+SIMULATION", *incdir_args,
         "-work", "work", *sources],
        cwd=output_directory,
        check=True,
    )


def open_waveform(waveform):
    if waveform.suffix == ".wlf":
        subprocess.Popen(
            ["vsim", "-view", waveform.name],
            cwd=waveform.parent,
        )
        return
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


def run_verilator(top_module, sources, output_directory, waveform, lint=False):
    oss_root = Path(r"C:\Users\soury\oss-cad-suite")
    verilator = oss_root / "bin" / "verilator_bin.exe"
    object_directory = output_directory / f"obj_{top_module}"

    if not verilator.is_file():
        raise FileNotFoundError(f"Verilator not found: {verilator}")

    if not waveform.is_absolute():
        waveform = output_directory / waveform

    waveform = waveform.resolve()
    waveform.parent.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    environment["VERILATOR_ROOT"] = (
        oss_root / "share" / "verilator"
    ).as_posix()

    environment["PATH"] = os.pathsep.join(
        [
            r"C:\Users\soury\mingw64\bin",
            str(oss_root / "bin"),
            str(oss_root / "lib"),
            r"C:\Program Files\Git\usr\bin",
            environment.get("PATH", ""),
        ]
    )

    make = shutil.which(
        "mingw32-make",
        path=environment["PATH"],
    )
    if not make:
        raise FileNotFoundError(
            "mingw32-make was not found on PATH."
        )
    environment["MAKE"] = make

    if lint:
        report = output_directory / "lint-report.sarif"

        subprocess.run(
            [
                verilator,
                "--lint-only",
                "-Wall",
                "-Wno-fatal",
                "--diagnostics-sarif-output",
                report,
                "--top-module",
                top_module,
                *sources,
            ],
            cwd=output_directory,
            env=environment,
            check=True,
        )

        print(f"Lint report: {report}")
        return None

    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "--trace",
            "-Wno-fatal",
            "--top-module",
            top_module,
            "--Mdir",
            object_directory,
            "-o",
            top_module,
            *sources,
        ],
        cwd=output_directory,
        env=environment,
        check=True,
    )

    executable = object_directory / f"{top_module}.exe"

    if not executable.is_file():
        raise FileNotFoundError(
            f"Verilator executable was not generated: {executable}"
        )

    subprocess.run(
        [executable, f"+wave={waveform.as_posix()}"],
        cwd=output_directory,
        env=environment,
        check=True,
    )

    return waveform


def main():
    args = parse_arguments()

    sources = validate_sources(args.sources)

    output_directory = args.out.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)

    if args.lint:
        run_verilator(
            args.top,
            sources,
            output_directory,
            args.wave,
            lint=True,
        )
        return 0

    if args.sim == "questa":
        setup_questa_environment()
        compile_questa(sources, output_directory, args.incdir)

        waveform = run_questa(
            args.top,
            output_directory,
            args.wave,
        )
    else:
        waveform = run_verilator(
            args.top,
            sources,
            output_directory,
            args.wave,
        )

    if args.gui:
        open_waveform(waveform)

    return 0

if __name__ == "__main__":
    main()
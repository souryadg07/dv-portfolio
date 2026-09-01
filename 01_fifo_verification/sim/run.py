#!/usr/bin/env python3
"""Compile and run a SystemVerilog testbench on Questa or Verilator.

Source files are given as positional arguments; the top module is inferred from
the last one unless --top says otherwise.

    python sim/run.py rtl/sync_fifo.sv tb/top/tb_v1.sv
    python sim/run.py rtl/sync_fifo.sv tb/top/tb_v1.sv --sim verilator
    python sim/run.py rtl/sync_fifo.sv tb/top/tb_v1.sv -D BUG_FULL_FLAG
    python sim/run.py rtl/sync_fifo.sv tb/top/tb_v1.sv --gui
    python sim/run.py rtl/sync_fifo.sv --lint

Both backends take the same +define+/+incdir+ arguments and both write a VCD via
the testbench $dumpfile block, so a waveform opens in GTKWave either way.

The exit code is 0 only when the tools succeed and the log is free of errors, so
this can be driven straight from a regression script.
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent

# Questa here is the Lattice OEM build: no randomize()/covergroup licence.
QUESTA_HINTS = [
    r"C:\lscc\radiant\2025.2\questasim\win64",
    r"C:\lscc\propel\2025.2.1\questasim\win64",
    r"C:\lscc\diamond\3.14\questasim\win64",
]
# Verilator and GTKWave both ship in the OSS CAD Suite bundle.
OSS_HINTS = [
    r"C:\oss-cad-suite\bin",
    r"C:\tools\oss-cad-suite\bin",
    os.path.expanduser(r"~\oss-cad-suite\bin"),
    r"C:\msys64\mingw64\bin",
]
# The OSS CAD Suite bundles no C++ compiler, and Verilator's --binary flow needs
# a stable libstdc++: GCC 16 is trunk and its libstdc++ omits the std::string
# move-constructor symbol the Verilated runtime links against, so the link fails
# with undefined references. Pin a stable GCC ahead of whatever is on PATH.
GCC_HINTS = [os.path.expanduser(r"~\mingw64\bin"), r"C:\mingw64\bin"]
# Verilator's verilated.mk is a POSIX makefile: it runs `uname -s` and its
# archive rule uses `if test ...; then`. GNU make only uses sh.exe if it can find
# one on PATH and otherwise falls back to cmd.exe, which parses neither -- it
# fails with "0 was unexpected at this time". So the build works from a shell
# that happens to have sh.exe on PATH (Git Bash) and breaks from one that does
# not (PowerShell, cmd). Put a POSIX shell on PATH so the terminal stops mattering.
SH_HINTS = [
    r"C:\Program Files\Git\usr\bin",
    r"C:\Program Files (x86)\Git\usr\bin",
    os.path.expanduser(r"~\AppData\Local\Programs\Git\usr\bin"),
]

# Lines that mean the run failed even when the tool exits 0 -- which vsim does
# after a $fatal, since the macro still reaches its own quit. vsim prefixes its
# transcript with "# ", so that prefix has to be optional here.
ERROR_RE = re.compile(
    r"^(?:# )?(?:\*\* (?:Error|Fatal)|%Error|ERROR:|UVM_(?:ERROR|FATAL) @|Errors: [1-9])",
    re.MULTILINE,
)


def find_tool(exe, env_var, hints):
    """Return the full path to exe, searching an override, PATH, then hints."""
    override = os.environ.get(env_var)
    if override:
        candidate = Path(override) / exe
        if candidate.exists():
            return candidate
    found = shutil.which(exe)
    if found:
        return Path(found)
    for hint in hints:
        for path in sorted(glob.glob(hint), reverse=True):  # newest version first
            candidate = Path(path) / exe
            if candidate.exists():
                return candidate
    return None


def require(exe, env_var, hints, install_hint):
    tool = find_tool(exe, env_var, hints)
    if not tool:
        sys.exit(f"error: {exe} not found. {install_hint}")
    return tool


def infer_top(sources):
    """First module declared in the last source file: by convention, the TB."""
    text = sources[-1].read_text(encoding="utf-8", errors="replace")
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.DOTALL)
    match = re.search(r"^\s*module\s+(\w+)", text, re.MULTILINE)
    if not match:
        sys.exit(f"error: no module found in {sources[-1]}; pass --top")
    return match.group(1)


def compile_args(args, sources, wave):
    """The +define+/+incdir+ flags, which Questa and Verilator both accept."""
    defines = list(args.define) + (["DUMP"] if wave else [])
    incdirs = [Path(d).resolve() for d in args.incdir] + [s.parent for s in sources]
    return [f"+define+{d}" for d in defines] + [
        f"+incdir+{d}" for d in sorted({str(d) for d in incdirs})
    ]


def preferred_gcc():
    """Directory of a stable g++ for Verilator's C++ flow; CXX_BIN overrides."""
    exe = "g++.exe" if os.name == "nt" else "g++"
    for hint in [os.environ.get("CXX_BIN")] + GCC_HINTS:
        if hint and (Path(hint) / exe).exists():
            return Path(hint)
    return None


def posix_shell_dir():
    """Directory holding sh.exe and uname.exe; SH_BIN overrides."""
    if os.name != "nt":
        return None
    for hint in [os.environ.get("SH_BIN")] + SH_HINTS:
        if hint and all((Path(hint) / e).exists() for e in ("sh.exe", "uname.exe")):
            return Path(hint)
    return None


def oss_env(tool):
    """Reproduce the OSS CAD Suite environment.bat setup for a subprocess.

    Its binaries load DLLs from lib/, and gtkwave needs the GTK/pixbuf paths, so
    invoking them straight off PATH is not enough.
    """
    env = os.environ.copy()
    root = tool.parent.parent
    if not (root / "share").is_dir():  # not an OSS CAD Suite layout; leave it alone
        return env
    gdk = root / "lib" / "gdk-pixbuf-2.0" / "2.10.0"
    path = [str(root / "bin"), str(root / "lib")]
    gcc = preferred_gcc()
    if gcc:
        path.insert(0, str(gcc))  # ahead of any other GCC already on PATH
    sh = posix_shell_dir()
    if sh:
        path.append(str(sh))  # only has to be findable, not to shadow the above
    env.update(
        YOSYSHQ_ROOT=f"{root}{os.sep}",
        # Forward slashes: make passes this through a shell that would otherwise
        # eat the backslashes, turning the path into one runtogether word.
        VERILATOR_ROOT=(root / "share" / "verilator").as_posix(),
        QT_PLUGIN_PATH=str(root / "lib" / "qt6" / "plugins"),
        GTK_EXE_PREFIX=str(root),
        GTK_DATA_PREFIX=str(root),
        GDK_PIXBUF_MODULEDIR=str(gdk / "loaders"),
        GDK_PIXBUF_MODULE_FILE=str(gdk / "loaders.cache"),
        PATH=os.pathsep.join(path + [env.get("PATH", "")]),
    )
    # verilator --binary shells out to $MAKE, which defaults to "make"; this box
    # only has mingw32-make, and the suite bundles no make of its own.
    if not shutil.which("make"):
        mingw = shutil.which("mingw32-make")
        if mingw:
            env["MAKE"] = mingw
    return env


def run(cmd, cwd, logfile, env=None):
    """Run a command, streaming its output to both the console and the log."""
    cmd = [str(c) for c in cmd]
    banner = "+ " + subprocess.list2cmdline(cmd)
    print(banner, flush=True)
    with open(logfile, "a", encoding="utf-8") as log:
        log.write(banner + "\n")
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        output = []
        for line in proc.stdout:
            sys.stdout.write(line)
            log.write(line)
            output.append(line)
        proc.wait()
    return proc.returncode, "".join(output)


def failed(rc, output):
    return rc or (1 if ERROR_RE.search(output) else 0)


def questa(args, sources, top, out, wave, logfile):
    bindir = require(
        "vlib.exe", "QUESTA_BIN", QUESTA_HINTS, "Set QUESTA_BIN to its win64 directory."
    ).parent
    work = "work"  # relative: vopt cannot parse an absolute library path

    if (out / work).exists():
        shutil.rmtree(out / work)
    rc, _ = run([bindir / "vlib.exe", work], out, logfile)
    if rc:
        return rc

    cmd = [bindir / "vlog.exe", "-sv", "-work", work] + compile_args(args, sources, wave)
    rc, output = run(cmd + sources, out, logfile)
    if failed(rc, output):
        return rc or 1

    # onerror/onbreak are only honoured inside a macro file, not a -do string;
    # without them a runtime error drops to the prompt and hangs the regression.
    do = ["onerror {quit -code 1}", "onbreak {quit -code 1}", "run -all", "quit -code 0"]
    script = out / "run.do"
    script.write_text("\n".join(do) + "\n", encoding="utf-8")

    cmd = [bindir / "vsim.exe", "-c", "-work", work, top, "-do", script.name]
    if wave:
        cmd += ["-voptargs=+acc", f"+wave={wave}"]  # +acc keeps signals visible
    rc, output = run(cmd, out, logfile)
    return failed(rc, output)


def verilator(args, sources, top, out, wave, logfile):
    # The `verilator` launcher is a Perl script, which Windows cannot exec;
    # verilator_bin is the real binary, and oss_env supplies its VERILATOR_ROOT.
    tool = require(
        "verilator_bin.exe" if os.name == "nt" else "verilator",
        "VERILATOR_BIN", OSS_HINTS,
        "Install the OSS CAD Suite (it bundles Verilator and GTKWave).",
    )
    env = oss_env(tool)
    objdir = out / f"obj_{top}"

    if args.lint:
        cmd = [tool, "--lint-only", "-Wall", "--top-module", top]
    else:
        # --binary implies --main --exe --build --timing; --timing is what carries
        # the testbench's # delays, which Verilator cannot schedule without it.
        # Warnings are fatal by default, so a lint nit would block every run;
        # --lint stays strict and is the gate instead.
        cmd = [tool, "--binary", "-j", "0", "-Wno-fatal", "--top-module", top,
               "--Mdir", objdir, "-o", top]
        if wave:
            cmd += ["--trace"]
    rc, output = run(cmd + compile_args(args, sources, wave) + sources, out, logfile, env)
    if args.lint or failed(rc, output):
        return failed(rc, output)

    exe = next((objdir / f"{top}{s}" for s in (".exe", "") if (objdir / f"{top}{s}").exists()), None)
    if not exe:
        sys.exit(f"error: Verilator built no executable in {objdir}")
    rc, output = run([exe] + ([f"+wave={wave}"] if wave else []), out, logfile, env)
    return failed(rc, output)


def lint(args, sources, top, out, logfile):
    return verilator(args, sources, top, out, None, logfile)


def open_gui(wave):
    """Open the recorded VCD in GTKWave."""
    tool = require(
        "gtkwave.exe" if os.name == "nt" else "gtkwave",
        "GTKWAVE_BIN", OSS_HINTS,
        "Install the OSS CAD Suite (it bundles Verilator and GTKWave).",
    )
    print(f"+ {tool} {wave}", flush=True)
    subprocess.Popen([str(tool), str(wave)], cwd=wave.parent, env=oss_env(tool))


def main():
    parser = argparse.ArgumentParser(
        description="Compile and run a SystemVerilog testbench.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "sources", nargs="+", type=Path, help="RTL and testbench files, in compile order"
    )
    parser.add_argument("--top", help="top module (default: inferred from the last source)")
    parser.add_argument(
        "--sim", choices=["questa", "verilator"], default="questa", help="simulator backend"
    )
    parser.add_argument(
        "--lint", action="store_true", help="run Verilator lint only, no simulation"
    )
    parser.add_argument(
        "-D", "--define", action="append", default=[], metavar="NAME",
        help="macro to define; repeatable (e.g. -D BUG_FULL_FLAG)",
    )
    parser.add_argument(
        "-I", "--incdir", action="append", default=[], metavar="DIR",
        help="extra include directory; repeatable",
    )
    parser.add_argument(
        "--out", type=Path, default=PROJECT / "sim" / "out",
        help="build directory for the work library and logs",
    )
    parser.add_argument("--wave", type=Path, help="VCD path (default: waves/<top>.vcd)")
    parser.add_argument(
        "--no-wave", dest="wave_enabled", action="store_false", help="skip waveform recording"
    )
    parser.add_argument(
        "--gui", action="store_true", help="open the waveform in GTKWave when the run finishes"
    )
    args = parser.parse_args()

    sources = [s.resolve() for s in args.sources]
    for source in sources:
        if not source.is_file():
            sys.exit(f"error: no such file: {source}")

    top = args.top or infer_top(sources)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)

    wave = None
    if args.wave_enabled and not args.lint:
        wave = (args.wave or PROJECT / "waves" / f"{top}.vcd").resolve()
        wave.parent.mkdir(parents=True, exist_ok=True)

    logfile = out / f"{top}.log"
    logfile.write_text("", encoding="utf-8")

    mode = "lint" if args.lint else args.sim
    print(f"top       : {top}")
    print(f"mode      : {mode}")
    print(f"defines   : {', '.join(args.define) or 'none'}")
    print(f"log       : {logfile}")
    print(f"wave      : {wave or 'disabled'}\n")

    if args.lint:
        rc = lint(args, sources, top, out, logfile)
    else:
        backend = questa if args.sim == "questa" else verilator
        rc = backend(args, sources, top, out, wave, logfile)

    print(f"\n{'PASS' if rc == 0 else 'FAIL'}  {top} ({mode})  log: {logfile}")
    if rc == 0 and args.gui and wave:
        open_gui(wave)
    return rc


if __name__ == "__main__":
    sys.exit(main())

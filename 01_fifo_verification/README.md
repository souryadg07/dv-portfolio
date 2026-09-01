# Project 1 — Synchronous FIFO Verification

Verification of a parameterised single-clock synchronous FIFO. The DUT and its
requirements are in [`rtl/sync_fifo.sv`](rtl/sync_fifo.sv) and
[`docs/dut_spec.md`](docs/dut_spec.md).

Everything runs through [`sim/run.py`](sim/run.py), with a thin
[`Makefile`](Makefile) over it for the common cases.

## Running

Invoke make as `mingw32-make` on this machine — there is no `make` on PATH.

```sh
mingw32-make                                  # run the testbench on Questa
mingw32-make SIM=verilator                    # same testbench on Verilator
mingw32-make wave                             # run, then open the VCD in GTKWave
mingw32-make lint                             # Verilator lint only, no simulation
mingw32-make DEFINES="BUG_FULL_FLAG"          # compile with macros defined
mingw32-make clean                            # remove sim/out and waves/*.vcd
```

`SIM` and `DEFINES` combine with any target, so `mingw32-make wave
SIM=verilator DEFINES="BUG_COUNT"` is valid.

### Calling the runner directly

The Makefile only hardcodes the source list. For anything else, call `run.py`
with the files you want, in compile order:

```sh
python sim/run.py rtl/sync_fifo.sv tb/top/tb_v1.sv
python sim/run.py rtl/sync_fifo.sv tb/top/tb_v1.sv --sim verilator
python sim/run.py rtl/sync_fifo.sv tb/top/tb_v1.sv -D BUG_FULL_FLAG -D BUG_COUNT
python sim/run.py rtl/sync_fifo.sv --lint --top sync_fifo
```

| Option | Meaning |
| --- | --- |
| `--sim {questa,verilator}` | Simulator backend. Default `questa`. |
| `--top NAME` | Top module. Defaults to the first module in the **last** source file, which by convention is the testbench. |
| `--lint` | Verilator `--lint-only -Wall`. Needs no C++ compiler. |
| `-D NAME` | Adds `+define+NAME`. Repeatable. |
| `-I DIR` | Extra include directory. Repeatable. Each source file's own directory is added automatically. |
| `--wave PATH` | VCD path. Default `waves/<top>.vcd`. |
| `--no-wave` | Skip waveform recording. |
| `--gui` | Open the VCD in GTKWave after a passing run. |
| `--out DIR` | Build directory. Default `sim/out`. |

## Output

| Path | Contents |
| --- | --- |
| `sim/out/<top>.log` | Full transcript of every tool invocation |
| `waves/<top>.vcd` | Waveform, readable by GTKWave |
| `sim/out/work/` | Questa work library |
| `sim/out/obj_<top>/` | Verilator build directory |

All of it is gitignored.

**The exit code is the pass/fail signal**: 0 only when every tool succeeded *and*
the log contains no error lines. A `$fatal` in the testbench still leaves `vsim`
exiting 0, so the log is scanned as well — this is what the bug-injection
regression matrix will key off, so drive `run.py` from scripts rather than
parsing its output.

## Waveforms

Both simulators emit the same VCD from one `` `ifdef DUMP `` block in the
testbench, which calls `$dumpfile` with a `+wave=<path>` plusarg. `run.py`
supplies both. Verilator's `--trace` records nothing without that block, so a new
top-level testbench needs to copy it.

## Toolchain

| Tool | Role | Location |
| --- | --- | --- |
| Questa (Lattice OEM) | Main SystemVerilog simulator, SVA, UVM | `C:\lscc\radiant\2025.2\questasim\win64` |
| Verilator 5.051 | Fast simulation, lint, CI | `~\oss-cad-suite\bin` |
| GTKWave | Waveform viewing | `~\oss-cad-suite\bin` |
| GCC 14.3.0 | C++ backend for Verilator | `~\mingw64\bin` |

`run.py` finds these itself. Override any of them with the `QUESTA_BIN`,
`VERILATOR_BIN`, `GTKWAVE_BIN` or `CXX_BIN` environment variables, each pointing
at the directory holding the executable.

Two constraints worth knowing before changing the setup:

- **GCC 14 is pinned deliberately.** The GCC 16 on this machine is a trunk build
  whose libstdc++ omits a `std::string` symbol the Verilated runtime links
  against, so Verilator fails at link time with it. `run.py` puts GCC 14 ahead of
  it on `PATH` for the Verilator subprocess only.
- **Questa's OEM licence blocks `randomize()` and `covergroup`**, and Verilator
  does not implement them either. Constrained-random stimulus and functional
  coverage — required by spec §22 and gated by §23 — need a third simulator,
  Vivado XSim, which is not yet installed.

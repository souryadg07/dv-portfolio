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

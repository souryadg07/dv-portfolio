# Questa and Verilator simulation flow.
#
#   mingw32-make                       # Run testbench on Questa
#   mingw32-make run                   # Run testbench on Questa
#   mingw32-make SIM=verilator         # Run testbench on Verilator
#   mingw32-make wave                  # Run Questa and open GTKWave
#   mingw32-make wave SIM=verilator    # Run Verilator and open GTKWave
#   mingw32-make lint                  # Run Verilator lint only
#   mingw32-make clean                 # Remove generated simulation files

PYTHON := python
RUNNER := ../common/scripts/run.py

RTL     := rtl/sync_fifo.sv
TB      := tb/top/tb_v1.sv
RTL_TOP := sync_fifo
TB_TOP  := tb_sync_fifo
OUT     := sim/out
WAVE    := waves.vcd
SIM     ?= questa
BUILD_LOG := verilator-build.log

SOURCES := $(RTL) $(TB)

.PHONY: all run wave lint clean

all: run

run:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TB_TOP) --out $(OUT) --sim $(SIM)

wave:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TB_TOP) --out $(OUT) --wave $(WAVE) --sim $(SIM) --gui

lint:
	$(PYTHON) $(RUNNER) $(RTL) --top $(RTL_TOP) --out $(OUT) --lint

clean:
	$(PYTHON) -c "import shutil, pathlib; shutil.rmtree('$(OUT)', ignore_errors=True); pathlib.Path('$(BUILD_LOG)').unlink(missing_ok=True)"
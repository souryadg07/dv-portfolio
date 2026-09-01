# Questa and Verilator simulation flow.
#
#   mingw32-make                       # Run on Questa
#   mingw32-make run                   # Run on Questa
#   mingw32-make SIM=verilator         # Run on Verilator
#   mingw32-make wave                  # Run on Questa and open GTKWave
#   mingw32-make wave SIM=verilator    # Run on Verilator and open GTKWave
#   mingw32-make clean                 # Remove generated simulation files

PYTHON := python
RUNNER := ../common/scripts/run.py

RTL  := rtl/sync_fifo.sv
TB   := tb/top/tb_v1.sv
TOP  := tb_sync_fifo
OUT  := sim/out
WAVE := waves.vcd
SIM  ?= questa

SOURCES := $(RTL) $(TB)

.PHONY: all run wave clean

all: run

run:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TOP) --out $(OUT) --sim $(SIM)

wave:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TOP) --out $(OUT) --wave $(WAVE) --sim $(SIM) --gui

clean:
	$(PYTHON) -c "import shutil; shutil.rmtree('$(OUT)', ignore_errors=True)"
# Minimal Questa simulation flow.
#
#   mingw32-make          # Run simulation
#   mingw32-make run      # Run simulation
#   mingw32-make wave     # Run simulation and open GTKWave
#   mingw32-make clean    # Remove generated files

PYTHON := python
RUNNER := ../common/scripts/run.py

RTL  := rtl/sync_fifo.sv
TB   := tb/top/tb_v1.sv
TOP  := tb_sync_fifo
OUT  := sim/out
WAVE := waves.vcd

SOURCES := $(RTL) $(TB)

.PHONY: all run wave clean

all: run

run:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TOP) --out $(OUT) --wave $(WAVE)

wave:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TOP) --out $(OUT) --wave $(WAVE) --gui

clean:
	$(PYTHON) -c "import shutil; shutil.rmtree('$(OUT)', ignore_errors=True)"
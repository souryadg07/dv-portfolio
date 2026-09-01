# Minimal Questa simulation flow.
#
#   mingw32-make
#   mingw32-make run
#   mingw32-make clean

PYTHON := python
RUNNER := sim/run.py

RTL := rtl/sync_fifo.sv
TB  := tb/top/tb_v1.sv
TOP := tb_sync_fifo
OUT := sim/out

SOURCES := $(RTL) $(TB)

.PHONY: all run clean

all: run

run:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TOP) --out $(OUT)

clean:
	$(PYTHON) -c "import shutil; shutil.rmtree('$(OUT)', ignore_errors=True)"
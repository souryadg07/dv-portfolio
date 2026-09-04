# Questa and Verilator simulation flow.
#
#   mingw32-make                       # Run testbench on Questa
#   mingw32-make run                   # Run testbench on Questa
#   mingw32-make SIM=verilator         # Run testbench on Verilator
#   mingw32-make wave                  # Run Questa and open GTKWave
#   mingw32-make wave SIM=verilator    # Run Verilator and open GTKWave
#   mingw32-make lint                  # Run Verilator lint only
#   mingw32-make clean                 # Remove generated simulation files
#	mingw32-make wave TB=tb/top/tb_v2.sv TB_TOP=tb_sync_fifo_v2 SRC=tb/interface/fifo_if.sv

PYTHON := python
RUNNER := ../common/scripts/run.py

RTL     := rtl/sync_fifo.sv
RTL_W_BUG := rtl/sync_fifo_with_bug.sv
TB      ?= tb/top/tb_v1.sv
SRC     ?=
RTL_TOP := sync_fifo
TB_TOP  ?= tb_sync_fifo
OUT     := sim/out
WAVE    := waves.vcd
SIM     ?= questa
BUILD_LOG := verilator-build.log
SOURCES_RTL_W_BUGS := $(RTL_W_BUG) $(SRC) $(TB)
SOURCES := $(RTL) $(SRC) $(TB)
INCDIRS ?= tb/txn tb/agent tb/tests

.PHONY: all run wave lint clean buggy_run

all: run

run:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TB_TOP) --out $(OUT) --sim $(SIM) --incdir $(INCDIRS)
wave:
	$(PYTHON) $(RUNNER) $(SOURCES) --top $(TB_TOP) --out $(OUT) --wave $(WAVE) --sim $(SIM) --gui --incdir $(INCDIRS)

lint:
	$(PYTHON) $(RUNNER) $(RTL) --top $(RTL_TOP) --out $(OUT) --lint

clean:
	$(PYTHON) -c "import shutil, pathlib; shutil.rmtree('$(OUT)', ignore_errors=True); pathlib.Path('$(BUILD_LOG)').unlink(missing_ok=True)"

buggy_run:
	$(PYTHON) $(RUNNER) $(SOURCES_RTL_W_BUGS) --top $(TB_TOP) --out $(OUT) --wave $(WAVE) --sim $(SIM) --gui --incdir $(INCDIRS)

# Build/run abstraction over sim/run.py.
#
#   make            # run the testbench on Questa
#   make SIM=verilator
#   make wave       # run, then open the VCD in GTKWave
#   make lint       # Verilator lint only
#   make DEFINES="BUG_FULL_FLAG BUG_COUNT"
#   make clean
#
# Only mingw32-make is installed on this machine, so invoke it as
# `mingw32-make` unless a `make` alias is on PATH.

PYTHON  ?= python
RUN     := $(PYTHON) sim/run.py
RTL     := rtl/sync_fifo.sv
TB      := tb/top/tb_v1.sv
SIM     ?= questa
DEFINES ?=

SOURCES := $(RTL) $(TB)
FLAGS   := --sim $(SIM) $(addprefix -D,$(DEFINES))

.PHONY: all run wave lint clean

all: run

run:
	$(RUN) $(SOURCES) $(FLAGS)

wave:
	$(RUN) $(SOURCES) $(FLAGS) --gui

lint:
	$(RUN) $(RTL) --lint --top sync_fifo

clean:
	$(PYTHON) -c "import shutil,glob,os; shutil.rmtree('sim/out',True); [os.remove(f) for f in glob.glob('waves/*.vcd')]"

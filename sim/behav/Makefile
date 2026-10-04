# Simulation flow: compiles and runs the testbench with Xcelium, opens waveforms
# in SimVision, and opens coverage in IMC. Includes encrypted-CPU bug-hunt targets.

INCLUDE_FILE_NAME ?= cpu.include
TOP ?= cpu_tb_top
PYTHON ?= python3
IMC ?= /tools/software/cadence/vmanageragl/25.09.020/tools.lnx86/vmgr/bin/imc

CURRENT_DIR := $(shell pwd)
WORKSPACE := $(CURRENT_DIR)/WORKSPACE

# The encrypted RTL requires SIM to select its simulation-safe declarations.
XRUN_FLAGS = -64bit -sv -linedebug -access +rwc \
             -timescale 1ns/10ps +define+SIM=1 +incdir+sym_links \
             -coverage all -licqueue -covoverwrite

SIM_PLUSARGS ?=
SEED ?= 1
LOGFILE ?= simulation.log
WAVE_PLUSARGS ?=
COV_TEST ?= cpu

# Encrypted CPU variant (0-2) used by the bug-hunt targets. The bug reports in
# testplan.md were produced with variant 2.
BUG_HUNT_VARIANT ?= 2

.PHONY: help clean link xrun bug_hunt simvision bug_hunt_simvision coverage run_and_view

help:
	@echo "  make xrun [SEED=n]              run the RISC-V CPU suite"
	@echo "  make bug_hunt [SEED=n|random]   run the encrypted CPU and collect failures"
	@echo "  make simvision                   open the CPU waveform"
	@echo "  make bug_hunt_simvision          open the encrypted-CPU waveform"
	@echo "  make coverage                    open the CPU coverage database"
	@echo "  make clean                       remove generated simulation files"
	@echo "  bug-hunt variant: $(BUG_HUNT_VARIANT) (override with BUG_HUNT_VARIANT=n)"

clean:
	@rm -rf $(WORKSPACE)

link:
	@mkdir -p $(WORKSPACE)/sym_links
	@rm -rf $(WORKSPACE)/sym_links/*
	@BUG_HUNT_VARIANT=$(BUG_HUNT_VARIANT) $(PYTHON) link_files.py $(INCLUDE_FILE_NAME)

xrun: link
	cd $(WORKSPACE) && \
	xrun $(XRUN_FLAGS) -svseed $(SEED) -f sym_links/sim_no_path.include \
	     -top $(TOP) -covtest $(COV_TEST) -logfile $(LOGFILE) \
	     +SEED_LABEL=$(SEED) $(WAVE_PLUSARGS) $(SIM_PLUSARGS)

bug_hunt:
	@echo "Bug-hunt variant $(BUG_HUNT_VARIANT)"
	@rm -rf $(WORKSPACE)/xcelium.d
	$(MAKE) xrun INCLUDE_FILE_NAME=bug_hunt.include \
		LOGFILE=bug_hunt.log WAVE_PLUSARGS=+BUG_HUNT_WAVES COV_TEST=bug_hunt \
		BUG_HUNT_VARIANT=$(BUG_HUNT_VARIANT) \
		SIM_PLUSARGS="$(SIM_PLUSARGS) +NO_STOP_ON_ERROR"

simvision:
	cd $(WORKSPACE) && simvision waves.shm &

bug_hunt_simvision:
	cd $(WORKSPACE) && simvision bug_hunt_waves.shm &

coverage:
	cd $(WORKSPACE) && $(IMC) -load cov_work/scope/$(COV_TEST) -load_refinement $(CURRENT_DIR)/exclusions.vRefine &

run_and_view: xrun simvision

.DEFAULT_GOAL := run_and_view

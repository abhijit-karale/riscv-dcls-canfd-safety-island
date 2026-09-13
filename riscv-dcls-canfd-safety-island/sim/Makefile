#=============================================================================
# File: Makefile
# Description: Production Build & Verification Automation Makefile for
#              Dual-Core Lockstep (DCLS) Safety Island with CAN-FD Controller.
# Supported Simulators: QuestaSim, Synopsys VCS, Cadence Xcelium, Verilator
# Supported Formal: Cadence JasperGold
#=============================================================================

SIM ?= questa
TEST ?= dcls_lockstep_fault_test
UVM_VERBOSITY ?= UVM_LOW
QUESTA_HOME ?= C:/questasim64_10.7c

# Colors for terminal reporting
CYAN  := \033[1;36m
GREEN := \033[1;32m
RED   := \033[1;31m
NC    := \033[0m

.PHONY: all sim_uvm sim_questa sim_vcs sim_xcelium formal clean help

all: sim_uvm

help:
	@echo "======================================================================"
	@echo " Makefile Targets for riscv-dcls-canfd-safety-island"
	@echo "======================================================================"
	@echo " make sim_uvm      : Run default UVM simulation (SIM=$(SIM), TEST=$(TEST))"
	@echo " make sim_questa   : Run simulation with Siemens QuestaSim"
	@echo " make sim_vcs      : Run simulation with Synopsys VCS"
	@echo " make sim_xcelium  : Run simulation with Cadence Xcelium"
	@echo " make formal       : Run Cadence JasperGold formal proof batch"
	@echo " make clean        : Clean simulation and formal artifacts"
	@echo "======================================================================"

# Universal sim_uvm dispatcher
sim_uvm:
ifeq ($(SIM),questa)
	$(MAKE) sim_questa
else ifeq ($(SIM),vcs)
	$(MAKE) sim_vcs
else ifeq ($(SIM),xcelium)
	$(MAKE) sim_xcelium
else
	@echo "Unsupported simulator: $(SIM)"
	@exit 1
endif

#-----------------------------------------------------------------------------
# 1. Siemens QuestaSim Flow
#-----------------------------------------------------------------------------
VLOG := $(QUESTA_HOME)/win64/vlog.exe
VSIM := $(QUESTA_HOME)/win64/vsim.exe
VLIB := $(QUESTA_HOME)/win64/vlib.exe

sim_questa:
	@echo -e "$(CYAN)>>> Compiling RTL and UVM Testbench with QuestaSim...$(NC)"
	@if not exist work $(VLIB) work
	$(VLOG) -sv -work work \
		+incdir+$(QUESTA_HOME)/verilog_src/uvm-1.2/src \
		$(QUESTA_HOME)/verilog_src/uvm-1.2/src/uvm_pkg.sv \
		-f filelist.f
	@echo -e "$(CYAN)>>> Executing UVM Test: $(TEST)...$(NC)"
	$(VSIM) -c -nodpiexports -voptargs="+acc" tb_top \
		-sv_lib $(QUESTA_HOME)/uvm-1.2/win64/uvm_dpi \
		+UVM_TESTNAME=$(TEST) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		-do "run -all; quit -f"

#-----------------------------------------------------------------------------
# 2. Synopsys VCS Flow
#-----------------------------------------------------------------------------
VCS_FLAGS := -sverilog -full64 -timescale=1ns/1ps -ntb_opts uvm-1.2 \
             +acc +vpi -debug_access+all -kdb -l vcs_comp.log

sim_vcs:
	@echo -e "$(CYAN)>>> Compiling and Running with Synopsys VCS...$(NC)"
	vcs $(VCS_FLAGS) -f filelist.f -top tb_top -o simv
	./simv +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERBOSITY) -l vcs_sim.log

#-----------------------------------------------------------------------------
# 3. Cadence Xcelium Flow
#-----------------------------------------------------------------------------
XRUN_FLAGS := -64bit -sv -uvm -timescale 1ns/1ps -access +rwc \
              -f filelist.f -top tb_top -licqueue

sim_xcelium:
	@echo -e "$(CYAN)>>> Compiling and Running with Cadence Xcelium...$(NC)"
	xrun $(XRUN_FLAGS) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERBOSITY) -l xrun.log

#-----------------------------------------------------------------------------
# 4. Formal Verification: Cadence JasperGold
#-----------------------------------------------------------------------------
formal:
	@echo -e "$(CYAN)>>> Launching Cadence JasperGold Formal Proofs...$(NC)"
	cd ../formal/scripts && jaspergold -batch -tcl jaspergold_run.tcl

#-----------------------------------------------------------------------------
# 5. Clean
#-----------------------------------------------------------------------------
clean:
	@echo -e "$(CYAN)>>> Cleaning build artifacts...$(NC)"
	rm -rf work transcript *.wlf *.vcd *.log *.rpt simv* csrc INCA_libs xcelium.d
	rm -rf ../formal/scripts/jgproject ../formal/scripts/*.rpt ../formal/scripts/*.log
	@echo -e "$(GREEN)>>> Clean completed.$(NC)"

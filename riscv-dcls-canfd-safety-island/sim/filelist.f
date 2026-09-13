#=============================================================================
# File: filelist.f
# Description: Unified compilation filelist for RTL, Formal SVA, and UVM TB.
#=============================================================================

# Include directories
+incdir+../rtl/core
+incdir+../rtl/canfd
+incdir+../rtl/cdc
+incdir+../tb
+incdir+../tb/env
+incdir+../tb/agents/canfd_agent
+incdir+../tb/agents/fault_agent
+incdir+../tb/sequences
+incdir+../tb/tests
+incdir+../formal/svalib

# RTL Sources
../rtl/cdc/async_fifo_gray.sv
../rtl/core/rv32i_core.sv
../rtl/core/dcls_comparator.sv
../rtl/canfd/canfd_crc.sv
../rtl/canfd/canfd_bit_timing.sv
../rtl/canfd/canfd_top.sv
../rtl/safety_island_top.sv

# Formal SVA Checker Bindings
../formal/svalib/dcls_assertions.sva

# Testbench Interfaces, Packages, and Top Harness
../tb/safety_island_if.sv
../tb/env/safety_island_tb_pkg.sv
../tb/tb_top.sv

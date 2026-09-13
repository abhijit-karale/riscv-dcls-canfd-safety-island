#=============================================================================
# File: jaspergold_run.tcl
# Description: Production JasperGold Formal Verification Script for
#              Dual-Core Lockstep (DCLS) Safety Island & CAN-FD Controller.
# Usage: jaspergold -batch -tcl scripts/jaspergold_run.tcl
# Tool: Cadence JasperGold Formal Verification
#=============================================================================

# 1. Clear session
clear -all

# 2. Set formal compilation flags
set_sv -version 2012
set_design_mode -module

# 3. Analyze RTL and SVA source files
analyze -sv \
    ../../rtl/cdc/async_fifo_gray.sv \
    ../../rtl/core/rv32i_core.sv \
    ../../rtl/core/dcls_comparator.sv \
    ../../rtl/canfd/canfd_crc.sv \
    ../../rtl/canfd/canfd_bit_timing.sv \
    ../../rtl/canfd/canfd_top.sv \
    ../../rtl/safety_island_top.sv \
    ../svalib/dcls_assertions.sva

# 4. Elaborate Top-Level Design
elaborate -top safety_island_top -bbox_a 4096

# 5. Define Primary Clocks
# Core domain: 200 MHz (Period = 5.0 ns)
clock clk_core -factor 1
# CAN domain: 40 MHz (Period = 25.0 ns, 5x slower)
clock clk_can  -factor 5

# 6. Define Resets
reset -expression {!rst_core_n} -name rst_core_n
reset -expression {!rst_can_n}  -name rst_can_n

# 7. Environment Modeling & Formal Assumptions
# Keep synchronous clear inactive unless testing recovery
assume -name a_alarm_clear_inactive {alarm_clear_n == 1'b1}

# Constrain external FIU inputs to valid ranges
assume -name a_fiu_valid_stage {fiu_ext_stage inside {2'b00, 2'b01, 2'b10, 2'b11}}

# 8. Configure Engines and Proof Strategies
set_engine_mode {Hp Ht B Tri AM}
set_proofgrid_max_jobs 4

# 9. Execute Unbounded Formal Proofs
puts "================================================================"
puts " Starting Unbounded Formal Verification of DCLS Safety Island..."
puts "================================================================"
prove -all

# 10. Generate Proof Results Report
report -summary -file jaspergold_proof_summary.rpt
report -results -file jaspergold_detailed_results.rpt

puts "================================================================"
puts " Formal Proof Execution Completed. Check jaspergold_proof_summary.rpt"
puts "================================================================"

exit

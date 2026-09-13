onerror {resume}
quietly WaveActivateNextPane {} 0

# Support both live simulation (/tb_top) and post-sim WLF viewer (vsim:/tb_top)
set ds [dataset current]
if {$ds eq "" || $ds eq "sim"} {
    set prefix "/tb_top"
} else {
    set prefix "$ds:/tb_top"
}

add wave -noupdate -divider {CLOCKS & RESETS}
add wave -noupdate -format Logic -color Cyan $prefix/clk_core
add wave -noupdate -format Logic -color Blue $prefix/clk_can
add wave -noupdate -format Logic -color Orange $prefix/rst_core_n
add wave -noupdate -format Logic -color Orange $prefix/rst_can_n

add wave -noupdate -divider {FAULT INJECTION UNIT (FIU)}
add wave -noupdate -format Logic -color Red $prefix/dut_if/fiu_en
add wave -noupdate -format Logic $prefix/dut_if/fiu_target_shadow
add wave -noupdate -format Literal -radix unsigned $prefix/dut_if/fiu_stage
add wave -noupdate -format Literal -radix unsigned $prefix/dut_if/fiu_bit_idx
add wave -noupdate -format Literal -radix hexadecimal $prefix/dut_if/fiu_mask

add wave -noupdate -divider {ASIL-D SAFETY & LOCKSTEP COMPARATOR}
add wave -noupdate -format Logic -color Yellow $prefix/u_dut/u_dcls_subsystem/mismatch_detected
add wave -noupdate -format Logic -color Magenta $prefix/dut_if/safe_state_alarm
add wave -noupdate -format Literal -radix hexadecimal $prefix/dut_if/fault_pc
add wave -noupdate -format Literal -radix hexadecimal $prefix/dut_if/fault_status
add wave -noupdate -format Logic $prefix/dut_if/alarm_clear_n

add wave -noupdate -divider {PRIMARY VS SHADOW RISC-V CORES}
add wave -noupdate -format Literal -color Green -radix hexadecimal $prefix/u_dut/u_dcls_subsystem/u_master_core/pc_q
add wave -noupdate -format Literal -color Green -radix hexadecimal $prefix/u_dut/u_dcls_subsystem/u_master_core/alu_result
add wave -noupdate -format Literal -color Cyan -radix hexadecimal $prefix/u_dut/u_dcls_subsystem/u_shadow_core/pc_q
add wave -noupdate -format Literal -color Cyan -radix hexadecimal $prefix/u_dut/u_dcls_subsystem/u_shadow_core/alu_result

add wave -noupdate -divider {CAN-FD CONTROLLER & BUS}
add wave -noupdate -format Logic -color Green $prefix/dut_if/can_tx
add wave -noupdate -format Logic -color Yellow $prefix/dut_if/can_rx
add wave -noupdate -format Literal -radix ASCII $prefix/u_dut/u_canfd_core/fsm_state

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {250000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 280
configure wave -valuecolwidth 120
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
wave zoom full

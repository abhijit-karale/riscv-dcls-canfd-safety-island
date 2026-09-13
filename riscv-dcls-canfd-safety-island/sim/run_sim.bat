@echo off
setlocal
echo =====================================================================
echo  Automotive Safety Island: RISC-V Lockstep + CAN-FD + FIU Simulation
echo =====================================================================
set QUESTA_HOME=C:\questasim64_10.7c
set PATH=%QUESTA_HOME%\win64;%PATH%

cd /d "%~dp0"
if not exist work vlib work

echo [1/2] Compiling RTL and UVM Testbench...
vlog -sv -work work +incdir+%QUESTA_HOME%/verilog_src/uvm-1.2/src %QUESTA_HOME%/verilog_src/uvm-1.2/src/uvm_pkg.sv -f filelist.f
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Compilation failed!
    pause
    exit /b %ERRORLEVEL%
)

echo [2/2] Running UVM Simulation (dcls_lockstep_fault_test)...
vsim -c -nodpiexports -voptargs="+acc" tb_top -sv_lib %QUESTA_HOME%/uvm-1.2/win64/uvm_dpi +UVM_TESTNAME=dcls_lockstep_fault_test +UVM_VERBOSITY=UVM_LOW +DUMP_VCD -do "log -r /*; run -all; quit -f"

echo =====================================================================
echo Simulation finished! Waveform saved to vsim.wlf and sim_trace.vcd.
echo Launch view_waves.bat to open QuestaSim Waveform Viewer.
echo =====================================================================
pause

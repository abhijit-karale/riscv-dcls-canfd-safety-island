@echo off
setlocal
set "QUESTA_HOME=C:\questasim64_10.7c"
set "PATH=%QUESTA_HOME%\win64;%PATH%"
set "SIM_DIR=c:\Users\abhij\OneDrive\Documents\Dual-Core Lockstep RISC-V Automotive Safety Island with CAN-FD Controller & Fault Injection Unit\riscv-dcls-canfd-safety-island\sim"
set "DASHBOARD=c:\Users\abhij\OneDrive\Documents\Dual-Core Lockstep RISC-V Automotive Safety Island with CAN-FD Controller & Fault Injection Unit\verification_waves_dashboard.html"

echo =====================================================================
echo Launching Waveform Viewers (Interactive Dashboard + QuestaSim GUI)
echo =====================================================================
start "" "%DASHBOARD%"

cd /d "%SIM_DIR%"
start "" "%QUESTA_HOME%\win64\vsim.exe" -gui -nodpiexports -voptargs="+acc" tb_top -sv_lib "%QUESTA_HOME%/uvm-1.2/win64/uvm_dpi" +UVM_TESTNAME=dcls_lockstep_fault_test -do "do wave.do; run -all; wave zoom full"

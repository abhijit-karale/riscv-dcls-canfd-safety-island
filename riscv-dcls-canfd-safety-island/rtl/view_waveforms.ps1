$questa = "C:\questasim64_10.7c\win64\vsim.exe"
$simDir = "c:\Users\abhij\OneDrive\Documents\Dual-Core Lockstep RISC-V Automotive Safety Island with CAN-FD Controller & Fault Injection Unit\riscv-dcls-canfd-safety-island\sim"
$dashboard = "c:\Users\abhij\OneDrive\Documents\Dual-Core Lockstep RISC-V Automotive Safety Island with CAN-FD Controller & Fault Injection Unit\verification_waves_dashboard.html"

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host " [1] Opening Interactive Waveform Dashboard in Browser..." -ForegroundColor Green
Start-Process $dashboard

Write-Host " [2] Launching QuestaSim GUI Waveform Viewer..." -ForegroundColor Green
Start-Process $questa -ArgumentList "-gui", "-nodpiexports", "-voptargs=+acc", "tb_top", "-sv_lib", "C:/questasim64_10.7c/uvm-1.2/win64/uvm_dpi", "+UVM_TESTNAME=dcls_lockstep_fault_test", "-do", "do wave.do; run -all; wave zoom full" -WorkingDirectory $simDir
Write-Host "=====================================================================" -ForegroundColor Cyan

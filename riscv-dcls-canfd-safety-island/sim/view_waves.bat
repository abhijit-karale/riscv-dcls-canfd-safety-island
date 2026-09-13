@echo off
setlocal
set QUESTA_HOME=C:\questasim64_10.7c
set PATH=%QUESTA_HOME%\win64;%PATH%
cd /d "%~dp0"
echo Opening QuestaSim Waveform Viewer with vsim.wlf and wave.do...
start "" "%QUESTA_HOME%\win64\vsim.exe" -view vsim.wlf -do wave.do

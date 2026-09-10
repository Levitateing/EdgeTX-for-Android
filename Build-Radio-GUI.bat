@echo off
REM EdgeTX ANDROID radio firmware — GUI or console one-shot
REM Prefer: Build-Radio-GUI.pyw (no console). This .bat can flash a console for GUI.
REM Console: Build-Radio-GUI.bat TX16S | H750
cd /d "%~dp0"

REM Ensure GUI script is UTF-8 with BOM (Chinese Windows + PS 5.1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ensure-radio-gui-utf8.ps1" >nul 2>&1

if /I "%~1"=="gui" goto :gui
if /I "%~1"=="" goto :gui
if /I "%~1"=="/gui" goto :gui

REM Console one-shot: Build-Radio-GUI.bat TX16S | H750
set "HW=%~1"
if /I "%HW%"=="TX16S" goto :console
if /I "%HW%"=="H750" goto :console
echo Unknown board: %HW%
echo Usage:
echo   Build-Radio-GUI.pyw       ^(GUI, no console^)
echo   Build-Radio-GUI.bat       ^(GUI via powershell^)
echo   Build-Radio-GUI.bat TX16S ^(console^)
echo   Build-Radio-GUI.bat H750  ^(console^)
pause
exit /b 1

:gui
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\Build-Radio-Gui.ps1"
exit /b %ERRORLEVEL%

:console
title EdgeTX Radio Firmware Build - %HW%
echo === Building PCB=ANDROID ANDROID_HW=%HW% ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-android-radio.ps1" -Hw %HW%
set "EC=%ERRORLEVEL%"
echo.
if %EC% equ 0 (
    echo === SUCCESS ===
    echo Staged next to APK:
    if /I "%HW%"=="TX16S" echo   radio\src\targets\android\output\firmware-tx16s.bin
    if /I "%HW%"=="H750"  echo   radio\src\targets\android\output\firmware-h750.bin
) else (
    echo === FAILED exit=%EC% ===
)
pause
exit /b %EC%

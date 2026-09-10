@echo off
REM EdgeTX wallpaper tool (GUI) — double-click to open.
setlocal
cd /d "%~dp0"
start "" pythonw "%~dp0Prepare-Wallpaper.pyw"

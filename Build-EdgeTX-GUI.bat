@echo off
REM EdgeTX Android build wizard — no console (uses pythonw).
cd /d "%~dp0"
where pythonw >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pythonw "%~dp0Build-EdgeTX-GUI.pyw"
) else (
    python "%~dp0Build-EdgeTX-GUI.pyw"
)
exit /b %ERRORLEVEL%

@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Local-Setup.ps1" -Action Account
if errorlevel 1 echo Postopek ni uspel. Shrani zgornje sporocilo napake.
pause

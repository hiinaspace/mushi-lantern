@echo off
"%~dp0mushi-lantern.exe" --xr-mode on -- --xr %*
exit /b %errorlevel%

@echo off
"%~dp0mushi-lantern.exe" --xr-mode off -- --desktop %*
exit /b %errorlevel%

@echo off
title Publicar no site da Eleva
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\ElevaSite\repo\pc\sincronizar.ps1" -Manual
echo.
pause

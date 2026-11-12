@echo off
rem Test du bouton GPU de GameBoost sur la vraie carte NVIDIA (droits administrateur), puis remise d'origine
cd /d "%~dp0"
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
title Test de la carte graphique
echo Test en cours (environ 20 secondes)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test_gpu.ps1" -Src "%~dp0..\source\GameBoost.ps1" -Out "%USERPROFILE%\Desktop\Test_GPU_GameBoost.txt"
start notepad "%USERPROFILE%\Desktop\Test_GPU_GameBoost.txt"

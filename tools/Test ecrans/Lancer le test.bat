@echo off
rem Test reel des ecrans GameBoost (sans droits administrateur). Resultat : Bureau\Test_Ecrans_GameBoost.txt
echo Test des ecrans GameBoost : chaque ecran secondaire va s'eteindre 3 secondes par methode, puis se rallumer.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0test_ecrans.ps1"
echo.
echo Termine. Le resultat est sur le Bureau : Test_Ecrans_GameBoost.txt
pause

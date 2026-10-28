@echo off
REM =====================================================================
REM  INICIAR-PAGINA.bat
REM  Doble clic para levantar la pagina en un servidor local y abrirla
REM  en el navegador. Usa servidor.ps1 (tiene que estar en esta carpeta).
REM =====================================================================
title San Roque Soporte y Web - Servidor local
cd /d "%~dp0"

if not exist "%~dp0index.html" (
  echo.
  echo   No encuentro index.html en esta carpeta.
  echo   Guarda este archivo .bat junto al index.html.
  echo.
  pause
  exit /b 1
)

if not exist "%~dp0servidor.ps1" (
  echo.
  echo   Falta el archivo servidor.ps1 en esta carpeta.
  echo.
  pause
  exit /b 1
)

REM Puerto inicial (si esta ocupado, el servidor busca el siguiente libre)
set PUERTO=8080

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0servidor.ps1" -Port %PUERTO%

echo.
pause

@echo off
rem Telecharge et lance le script d'installation du pack All of Create Aeronautics.
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; $f = Join-Path $env:TEMP 'aeronautics-installer.ps1'; Invoke-WebRequest -UseBasicParsing 'https://milograbie.github.io/aeronautics-pack/client/installer.ps1' -OutFile $f; & $f"

@echo off
set "PSPath=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
echo Running script to stitch videos...
"%PSPath%" -NoProfile -ExecutionPolicy Bypass -File "C:\Users\GOONER MCEDGEWOOD\Desktop\video stitcher\video_stitcher.ps1"
echo Video stitching completed.
pause
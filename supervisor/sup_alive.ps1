# How many duo loops are running? (read by supervisor/watch.sh)
#   powershell -NoProfile -File supervisor/sup_alive.ps1   -> "SUP=1"
# 0 = the duos are stopped; more than the duos of config/duos.txt = a duplicate to stop
# (bin/harness/stop-all.ps1 -Definitive in its folder).
$n = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '\\bin\\harness\\duo\.ps1' }).Count
Write-Output "SUP=$n"

@echo off
title v2rayN Reset + Setup
net session >nul 2>&1 || (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText('%~f0'); $a=$s.LastIndexOf('#PS_START')+9; $b=$s.LastIndexOf('#PAYLOAD_BEGIN'); $env:SELF_BAT='%~f0'; iex $s.Substring($a,$b-$a)"
echo.
pause
exit /b

#PS_START
$ErrorActionPreference = 'SilentlyContinue'
function Say($m){ Write-Host "==> $m" -ForegroundColor Cyan }

# 1) Find v2rayN: C:\app first, then search elsewhere (newest version wins)
$exe = $null
if (Test-Path 'C:\app\v2rayN\v2rayN.exe') { $exe = 'C:\app\v2rayN\v2rayN.exe' }
if (-not $exe) {
  $found = Get-ChildItem 'C:\app' -Recurse -Depth 3 -Filter v2rayN.exe -ErrorAction SilentlyContinue
  if (-not $found) {
    Say "Not in C:\app - searching other places..."
    $roots = 'C:\v2rayN', "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:LOCALAPPDATA", "$env:APPDATA",
             "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Documents", 'C:\', 'D:\', 'E:\'
    $found = foreach ($r in $roots) { if (Test-Path $r) { Get-ChildItem $r -Recurse -Depth 3 -Filter v2rayN.exe -ErrorAction SilentlyContinue } }
  }
  $exe = ($found | Sort-Object { try { [version]$_.VersionInfo.FileVersion } catch { [version]'0.0' } } -Descending | Select-Object -First 1).FullName
}
if (-not $exe) { Write-Host "v2rayN.exe not found. Extract v2rayN (e.g. to C:\app\v2rayN) and run this again." -ForegroundColor Red; return }
$root = Split-Path $exe
Say "v2rayN found: $exe  (version $((Get-Item $exe).VersionInfo.FileVersion))"

# 2) Stop v2rayN and its cores
Say "Stopping v2rayN..."
Get-Process v2rayN,xray,sing-box,mihomo -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3

# 3) Remove leftover TUN adapters
Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'xray_tun|singbox_tun|v2rayN' } |
  ForEach-Object { pnputil /remove-device $_.InstanceId | Out-Null }

# 4) Full reset of v2rayN data (servers, subscriptions, settings, logs, cache)
Say "Resetting v2rayN data..."
foreach ($d in 'guiConfigs','binConfigs','guiTemps','guiLogs') {
  if (Test-Path "$root\$d") { Remove-Item "$root\$d" -Recurse -Force }
}

# 5) Unpack and apply new settings
Say "Applying new settings..."
$all = [IO.File]::ReadAllText($env:SELF_BAT)
$m = '#PAYLOAD' + '_BEGIN'
$b64 = $all.Substring($all.LastIndexOf($m) + $m.Length).Trim()
$tmp = Join-Path $env:TEMP ('v2rayN-setup-' + [guid]::NewGuid())
New-Item -ItemType Directory $tmp -Force | Out-Null
[IO.File]::WriteAllBytes("$tmp\p.zip", [Convert]::FromBase64String($b64))
Expand-Archive "$tmp\p.zip" "$tmp\x" -Force
New-Item -ItemType Directory "$root\guiConfigs", "$root\bin" -Force | Out-Null
Copy-Item "$tmp\x\guiConfigs\*" "$root\guiConfigs\" -Force
Remove-Item $tmp -Recurse -Force
if (-not (Test-Path "$root\guiConfigs\guiNDB.db")) { Write-Host "Failed to write settings." -ForegroundColor Red; return }

# 5b) Download Iran rules (geoip.dat / geosite.dat) from GitHub, with retry + resume + mirrors
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$base = @(
  'https://github.com/Chocolate4U/Iran-v2ray-rules/releases/latest/download',
  'https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release',
  'https://cdn.jsdelivr.net/gh/Chocolate4U/Iran-v2ray-rules@release'
)
$geoOk = $true
foreach ($f in @(@{n='geosite.dat'; min=4MB}, @{n='geoip.dat'; min=8MB})) {
  $dst = "$root\bin\$($f.n)"; $part = "$dst.part"; $done = $false
  Remove-Item $part -Force -ErrorAction SilentlyContinue
  for ($try = 1; $try -le 4 -and -not $done; $try++) {
    foreach ($b in $base) {
      Say "Downloading $($f.n) (try $try) from $(([uri]$b).Host)..."
      & curl.exe -L -s -S --fail --retry 3 --retry-delay 2 --connect-timeout 20 -C - -o $part "$b/$($f.n)" 2>$null
      if ((Test-Path $part) -and (Get-Item $part).Length -ge $f.min) { $done = $true; break }
    }
  }
  if ($done) { Move-Item $part $dst -Force; Say "$($f.n) OK ($([math]::Round((Get-Item $dst).Length/1MB,1)) MB)" }
  else { Remove-Item $part -Force -ErrorAction SilentlyContinue; $geoOk = $false; Write-Host "Could not download $($f.n)." -ForegroundColor Yellow }
}

# 6) Desktop shortcut (run as admin is needed for TUN) + start
$lnkPath = "$([Environment]::GetFolderPath('Desktop'))\v2rayN.lnk"
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
$lnk.TargetPath = $exe; $lnk.WorkingDirectory = $root; $lnk.Save()
$bytes = [IO.File]::ReadAllBytes($lnkPath); $bytes[0x15] = $bytes[0x15] -bor 0x20; [IO.File]::WriteAllBytes($lnkPath, $bytes)
Say "Starting v2rayN (admin)..."
Start-Process $exe -WorkingDirectory $root

Write-Host ""
Write-Host "DONE. Add your server in v2rayN (Ctrl+V) and connect." -ForegroundColor Green
Write-Host "Settings: TUN on | Routing = IR Direct | Iran DNS direct, others DoH via VPN | IPv4 only | Fragment off" -ForegroundColor Green
if (-not $geoOk) {
  Write-Host ""
  Write-Host "WARNING: Iran rules were not downloaded (internet/GitHub problem)." -ForegroundColor Red
  Write-Host "Connect any VPN and run this file again, or v2rayN may fail to start (geosite:ir missing)." -ForegroundColor Red
}
#PAYLOAD_BEGIN
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
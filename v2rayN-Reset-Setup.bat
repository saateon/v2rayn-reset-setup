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
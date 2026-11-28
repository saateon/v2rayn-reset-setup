@echo off
title v2rayN Reset + Setup v1.1.0
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
function Warn($m){ Write-Host "==> $m" -ForegroundColor Yellow }
function Get-Json($u){ try { $t = & curl.exe -s -m 8 -H 'User-Agent: v2rayn-reset-setup' $u; ($t -join "`n") | ConvertFrom-Json } catch { $null } }

# 0) Version banner + script update check
$ver = '1.1.0'
Write-Host ""
Write-Host "================ v2rayN Reset + Setup  v$ver ================" -ForegroundColor Green
$rv = ((& curl.exe -s -m 6 'https://raw.githubusercontent.com/saateon/v2rayn-reset-setup/main/VERSION') -join '').Trim()
if ($rv -match '^\d+\.\d+\.\d+$') {
  if ([version]$rv -gt [version]$ver) { Warn "A newer script exists: v$rv - get it from github.com/saateon/v2rayn-reset-setup" }
  else { Say "Script is up to date (v$ver)." }
} else { Warn "Script update check skipped (GitHub not reachable)." }

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
$inst = (Get-Item $exe).VersionInfo.FileVersion
Say "v2rayN found: $exe"
$rel = Get-Json 'https://api.github.com/repos/2dust/v2rayN/releases/latest'
if ($rel.tag_name) {
  $lat = $rel.tag_name.TrimStart('v')
  $old = $false; try { $old = [version]$lat -gt [version]$inst } catch {}
  if ($old) { Warn "v2rayN installed: $inst | latest: $lat  -> UPDATE AVAILABLE (github.com/2dust/v2rayN/releases)" }
  else { Say "v2rayN installed: $inst | latest: $lat  -> up to date" }
} else { Warn "v2rayN installed: $inst | latest: unknown (GitHub not reachable)" }

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
$grel = Get-Json 'https://api.github.com/repos/Chocolate4U/Iran-v2ray-rules/releases/latest'
if ($grel.tag_name) { Say "Iran rules release: $($grel.tag_name) ($($grel.published_at))" }
$n = 0
foreach ($f in @(@{n='geosite.dat'; min=4MB}, @{n='geoip.dat'; min=8MB})) {
  $dst = "$root\bin\$($f.n)"; $part = "$dst.part"; $done = $false
  Remove-Item $part -Force -ErrorAction SilentlyContinue
  $n++; Write-Host ""; Say "[$n/2] $($f.n)  (expected at least $([int]($f.min/1MB)) MB)"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  for ($try = 1; $try -le 4 -and -not $done; $try++) {
    foreach ($b in $base) {
      Say "Try $try/4 - source: $(([uri]$b).Host)"
      & curl.exe -L --progress-bar --fail --retry 3 --retry-delay 2 --connect-timeout 20 -C - -o $part "$b/$($f.n)"
      if ((Test-Path $part) -and (Get-Item $part).Length -ge $f.min) { $done = $true; break }
    }
  }
  if ($done) { Move-Item $part $dst -Force; Say "$($f.n) OK - $([math]::Round((Get-Item $dst).Length/1MB,1)) MB in $([int]$sw.Elapsed.TotalSeconds)s" }
  else { Remove-Item $part -Force -ErrorAction SilentlyContinue; $geoOk = $false; Write-Host "Could not download $($f.n)." -ForegroundColor Yellow }
}

# 5c) Disable IPv6 on adapters (IPv6 bypasses IPv4-only TUN and can leak the real IP via WebRTC). Undo: Enable-NetAdapterBinding -Name * -ComponentID ms_tcpip6
Say "Disabling IPv6 on network adapters (WebRTC leak protection)..."
Disable-NetAdapterBinding -Name * -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue

# 6) Desktop shortcut (run as admin is needed for TUN) + start
$lnkPath = "$([Environment]::GetFolderPath('Desktop'))\v2rayN.lnk"
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
$lnk.TargetPath = $exe; $lnk.WorkingDirectory = $root; $lnk.Save()
$bytes = [IO.File]::ReadAllBytes($lnkPath); $bytes[0x15] = $bytes[0x15] -bor 0x20; [IO.File]::WriteAllBytes($lnkPath, $bytes)
Say "Starting v2rayN (admin)..."
Start-Process $exe -WorkingDirectory $root

Write-Host ""
Write-Host "DONE (script v$ver, v2rayN $inst). Add your server in v2rayN (Ctrl+V) and connect." -ForegroundColor Green
Write-Host "Settings: TUN on | Routing = IR Direct | Iran DNS direct, others DoH via VPN | IPv4 only | STUN blocked | IPv6 off | Fragment off" -ForegroundColor Green
if (-not $geoOk) {
  Write-Host ""
  Write-Host "WARNING: Iran rules were not downloaded (internet/GitHub problem)." -ForegroundColor Red
  Write-Host "Connect any VPN and run this file again, or v2rayN may fail to start (geosite:ir missing)." -ForegroundColor Red
}
#PAYLOAD_BEGIN
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

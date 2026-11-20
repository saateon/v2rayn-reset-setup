# v2rayN Reset + Setup

یک دبل‌کلیک: v2rayN را کامل ریست می‌کند و تنظیمات (TUN، روتینگ ایران، DNS) را اعمال می‌کند.
One double-click: fully resets v2rayN on Windows and applies TUN, Iran-direct routing and split DNS.

## چه می‌کند / What it does
1. Finds v2rayN: `C:\app\v2rayN` first, then other drives/folders (newest version wins)
2. Stops v2rayN and its cores, removes leftover TUN adapters
3. **Wipes all v2rayN data** (servers, subscriptions, settings, logs)
4. Applies settings: TUN on · Fragment off · one routing profile **`IR Direct`** (Iran domains/IPs direct, LAN direct, ads & QUIC blocked, everything else proxied) · Iran DNS direct, other DNS via DoH through the proxy · IPv4 only
5. Downloads `geosite.dat` / `geoip.dat` (Iran rules) from [Chocolate4U/Iran-v2ray-rules](https://github.com/Chocolate4U/Iran-v2ray-rules) with retry, resume and 3 mirrors
6. Creates a desktop shortcut (run as admin) and starts v2rayN

## استفاده / Usage
Download `v2rayN-Reset-Setup.bat`, double-click, accept UAC, then add your server (Ctrl+V).

> ⚠️ **All existing servers and settings are deleted.** v2rayN must already be extracted on the machine.
> If the geo download fails, connect any VPN and run it again. No servers or credentials are included.

## License
MIT
# IEM Mixer

A mobile web app for controlling individual monitor mixes on a Behringer X32. Each musician opens a URL on their phone to adjust their own in-ear mix without touching the console.

---

## Install

Replace `192.168.1.100` with your X32's IP address.

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/cgamache/iem-mixer-releases/main/install.sh | bash -s -- --x32-ip 192.168.1.100
```

### Windows

Run in an elevated PowerShell prompt (right-click → Run as Administrator):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cgamache/iem-mixer-releases/main/install.ps1))) -X32Ip 192.168.1.100
```

---

## Connect

Once running, musicians open a browser on their phone and go to:

```
http://<computer-ip>:5000/monitor/<bus-number>
```

The computer must be on the same network as the X32. Musicians only need to reach the computer — not the X32 directly.

---

## Options

| Flag | Platform | Description |
|------|----------|-------------|
| `--x32-ip <ip>` | macOS/Linux | X32 IP address (prompted if omitted) |
| `--no-service` | macOS/Linux | Install files only, skip service registration |
| `--dry-run` | macOS/Linux | Print what would happen without doing it |
| `-X32Ip <ip>` | Windows | X32 IP address (prompted if omitted) |
| `-NoService` | Windows | Install files only, skip service registration |
| `-DryRun` | Windows | Print what would happen without doing it |

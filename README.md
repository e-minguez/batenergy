# batenergy (fork)

Fork of [batenergy](https://github.com/equaeghe/batenergy) by Erik Quaeghebeur.

Battery drain monitor for suspend/resume. Tracks how much battery was consumed during sleep and shows the stats via desktop notification after resuming.

## Changes from original

- **Desktop notification on resume** — sends a `notify-send` popup with drain stats after waking from sleep
- **Charging detection** — skips measurement when the battery is plugged in and charging (checks `BAT*/status`)
- **Bug fixes** — fixes array path expansion bugs (`BAT*`, `A*` globs now resolve correctly)
- **inotify-based notification** — uses systemd path units with kernel inotify, no polling or cron
- **Installation script** — `setup.sh` with `install`/`uninstall`/`status` commands
- **Improved output** — includes full duration breakdown, energy difference, and average drain rate

## Features

- Tracks energy consumption during suspend (before/after comparison)
- Skips measurement when battery is charging (plugged in)
- Desktop notification with drain rate (mW, %/h) after resume
- Works with Wayland notification daemons (mako, dunst, swaync, etc.) via D-Bus
- Zero CPU overhead — inotify is event-driven

## Requirements

- Linux with `/sys/class/power_supply/BAT*`
- `bc` (for percentage calculations)
- `notify-send` (for desktop notifications)
- systemd (for sleep hooks and user services)
- A notification daemon (mako, dunst, swaync, etc.)

## Installation

```bash
sudo bash setup.sh install
```

Then edit `/usr/local/bin/batenergy.sh` and set your username:

```bash
USER="your-username"
```

## Uninstallation

```bash
sudo bash setup.sh uninstall
```

## Manual Setup

If you prefer not to use the setup script:

1. Copy the script to `/usr/local/bin/batenergy.sh` and make it executable.
2. Set `USER` to your username in the script.
3. Create a symlink in the systemd-sleep directory:
   ```bash
   sudo ln -sf /usr/local/bin/batenergy.sh /etc/systemd/system-sleep/batenergy.sh
   ```
4. Install and enable the user-level systemd units:
   ```bash
   cp batenergy-notify.{path,service} ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now batenergy-notify.path
   ```

## How It Works

The script is invoked by `systemd-sleep` with two arguments:

| Stage | Arguments | What happens |
|-------|-----------|-------------|
| Before suspend | `pre suspend` | Saves timestamp + battery energy to a temp file |
| After resume | `post suspend` | Reads saved values, calculates drain, writes message to a file |

The user-level systemd `batenergy-notify.path` watches for the notification file and triggers `batenergy-notify.service` which sends the desktop notification via `notify-send` in the user's D-Bus session.

## Example Output

```
Currently on battery.
Duration of 0 days 0 hours 6 minutes sleeping (suspend).
Energy difference = 44520 - 45000
Battery energy change of -1.0 % (-480 mWh) at an average rate of -16.00 %/h (-480 mW).
```

## Testing

```bash
# Simulate pre-suspend
sudo batenergy.sh pre suspend

# Simulate post-suspend (requires the pre data to exist)
sudo batenergy.sh post suspend
```

## Files

| File | Purpose |
|------|---------|
| `batenergy.sh` | Main script (runs as root via systemd-sleep) |
| `batenergy-notify.path` | Watches for notification file via inotify (user systemd) |
| `batenergy-notify.service` | Sends desktop notification (user systemd) |
| `setup.sh` | Installation script |

## Credits

Original script by [Erik Quaeghebeur](https://github.com/equaeghe/batenergy).
Inspired by [Oliver Machacik's batdistrack](https://github.com/oliver-machacik/batdistrack).

## License

GPLv3 — same as the original [batenergy](https://github.com/equaeghe/batenergy).

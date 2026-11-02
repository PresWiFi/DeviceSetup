# DeviceSetup

Two scripts that install my standard set of apps on a new machine.

| Script | Runs on | Uses |
|---|---|---|
| `install.ps1` | Windows 10/11 | winget (+ Microsoft Store via winget), WSL, npm |
| `install.sh` | macOS and Linux | macOS: Homebrew + Mac App Store (`mas`). Linux: apt, dnf, pacman or zypper, vendor repos, Flathub |

Both scripts are safe to run again. Anything already installed is skipped, and a
summary at the end lists what was installed, skipped and failed. Each run writes a
log to your home folder (`devicesetup-<date>.log`).

## Windows

Open PowerShell **as Administrator** (so installers don't each ask for UAC):

```powershell
irm https://raw.githubusercontent.com/PresWiFi/DeviceSetup/main/install.ps1 -OutFile $env:TEMP\install.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\install.ps1
```

Or from a clone:

```powershell
.\install.ps1 -DryRun                       # show what would be installed
.\install.ps1                               # install everything
.\install.ps1 -Skip Valve.Steam,Google.AndroidStudio,wsl
.\install.ps1 -List                         # print the app list
```

`-Skip` takes winget IDs or app names. If winget isn't set up yet (fresh install,
LTSC, Windows Sandbox), the script registers or installs it first.

## macOS and Linux

```bash
curl -fsSL https://raw.githubusercontent.com/PresWiFi/DeviceSetup/main/install.sh | bash
```

Or from a clone:

```bash
./install.sh --dry-run              # show what would be installed
./install.sh                        # install everything
./install.sh --skip steam,ollama    # skip by key (see --list)
./install.sh --no-gui               # CLI tools only
./install.sh --verbose              # show installer output on screen
./install.sh --list                 # print the app list for this OS
```

Run it as your normal user. It asks for your password through `sudo` when needed.

**macOS:** installs the Xcode Command Line Tools and Homebrew if missing, then the
formulae, casks and Mac App Store apps. Apps already in `/Applications` (installed
by hand or from a .dmg) are left alone. Sign in to the App Store app before running
so the `mas` installs work.

**Linux:** reads `/etc/os-release` to work out the distro family, then uses its
package manager:

| Family | Package manager | Tested on |
|---|---|---|
| Debian, Ubuntu, Mint, Pop!_OS | apt | Ubuntu 24.04, Ubuntu 26.04, Debian 13 |
| Fedora, RHEL, Alma, Rocky | dnf | Fedora 44 |
| Arch, Manjaro, EndeavourOS | pacman | Arch Linux |
| openSUSE | zypper | openSUSE Tumbleweed |

CLI tools come from the distro. 1Password, Chrome, VS Code, GitHub CLI and Docker
come from the vendor's own repo where there is one. Tailscale, Ollama, Starship,
nvm and Claude Code use their official install scripts. The other GUI apps come from
Flathub. On WSL, GUI apps are off by default (pass `--gui` to include them), and if Docker
Desktop is installed on Windows the script uses its WSL integration instead of
installing a second Docker Engine.

## What gets installed

| App | Windows | macOS | Linux |
|---|---|---|---|
| 1Password | ✓ | ✓ | ✓ (vendor repo / tarball) |
| 1Password CLI | | ✓ | ✓ |
| 1Password for Safari | | ✓ (App Store) | |
| Google Chrome | ✓ | ✓ | ✓ (vendor repo; Flathub on Arch) |
| Obsidian | ✓ | ✓ | ✓ (Flathub) |
| Raycast | | ✓ | |
| PowerToys | ✓ | | |
| ONLYOFFICE | ✓ | | ✓ (Flathub) |
| Google Drive | ✓ | | |
| Photomator | | ✓ (App Store) | |
| Discord | ✓ | ✓ | ✓ (Flathub) |
| Telegram | ✓ | ✓ | ✓ (Flathub) |
| Microsoft Teams | ✓ | | |
| Spotify | | ✓ | ✓ (Flathub) |
| Steam | ✓ | ✓ | ✓ (Flathub) |
| Tailscale | ✓ | ✓ | ✓ |
| Syncthing | ✓ | ✓ | ✓ |
| LocalSend | ✓ | | ✓ (Flathub) |
| Blip | ✓ (Store) | | |
| Moonlight | | ✓ | ✓ (Flathub) |
| Apollo | ✓ | | |
| Parsec | ✓ | | ✓ (Flathub) |
| Remote Desktop Manager | | ✓ | |
| Windows App (RDP) | | ✓ (App Store) | |
| Amphetamine, AutoMounter | | ✓ (App Store) | |
| BetterDisplay | | ✓ | |
| 7-Zip, ShareX, WinDirStat | ✓ (all three) | | 7-Zip only |
| Apple Devices | ✓ (Store) | | |
| Visual Studio Code | ✓ | ✓ | ✓ (vendor repo; Flathub on Arch) |
| Terminal | Windows Terminal | Warp | (distro's own) |
| PowerShell 7 | ✓ | | |
| Git | ✓ | via Xcode CLT | ✓ |
| GitHub CLI | ✓ | | ✓ |
| GitHub Desktop | ✓ | | |
| Docker | Docker Desktop | CLI (`brew docker`) | Docker Engine |
| Node.js | Node LTS | nvm + LTS | nvm + LTS |
| Python | 3.14 + launcher | | python3 + pip |
| Xcode | | ✓ (App Store) | |
| Android Studio | ✓ | | ✓ (Flathub) |
| MSYS2 | ✓ | | |
| WSL + Ubuntu 24.04 | ✓ | | |
| Claude (desktop) | ✓ | | |
| Claude Code | ✓ | ✓ | ✓ |
| Codex | ✓ | ✓ | ✓ (npm) |
| OpenCode | Desktop + CLI (npm) | | CLI (npm) |
| Ollama | ✓ | | ✓ |
| btop, fastfetch, ripgrep | ✓ | | ✓ |
| Starship | ✓ | | ✓ |
| Oh My Posh | ✓ | | |

Games and launchers, drivers, and anything that ships with the OS are left out on
purpose.

## Changing the list

- **Windows:** edit the `$Apps` array at the top of `install.ps1` (find IDs with
  `winget search <name>`).
- **macOS:** edit `MAC_FORMULAE`, `MAC_CASKS` and `MAC_APPSTORE` near the top of
  `install.sh` (find App Store IDs with `mas search <name>`).
- **Linux:** edit `linux_main` in `install.sh`. Flathub apps are a `key|Name|app-id`
  list at the end of it.

# DeviceSetup

Installs my standard apps on a new machine.

| Script | OS | Uses |
|---|---|---|
| `install.ps1` | Windows 10/11 | winget (incl. Store), WSL, npm |
| `install.sh` | macOS, Linux | macOS: Homebrew, `mas`. Linux: apt/dnf/pacman/zypper, vendor repos, Flathub |

Safe to re-run: installed apps are skipped. Ends with an installed/skipped/failed summary and logs to `~/devicesetup-<date>.log`.

## Windows

Admin PowerShell:

```powershell
irm https://raw.githubusercontent.com/PresWiFi/DeviceSetup/main/install.ps1 -OutFile $env:TEMP\install.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\install.ps1
```

From a clone:

```powershell
.\install.ps1 -DryRun
.\install.ps1
.\install.ps1 -Skip Valve.Steam,Google.AndroidStudio,wsl   # winget IDs or names
.\install.ps1 -List
```

Installs winget first if missing (LTSC, Sandbox, fresh installs).

## macOS and Linux

Run as your normal user (uses `sudo` when needed):

```bash
curl -fsSL https://raw.githubusercontent.com/PresWiFi/DeviceSetup/main/install.sh | bash
```

From a clone:

```bash
./install.sh --dry-run
./install.sh
./install.sh --skip steam,ollama    # keys from --list
./install.sh --no-gui               # CLI tools only
./install.sh --verbose
./install.sh --list
```

**macOS:** installs Xcode CLT and Homebrew if missing. Skips apps already in `/Applications`. Sign in to the App Store first for `mas`.

**Linux:** picks the package manager from `/etc/os-release`.

| Family | Package manager | Tested on |
|---|---|---|
| Debian, Ubuntu, Mint, Pop!_OS | apt | Ubuntu 24.04, Ubuntu 26.04, Debian 13 |
| Fedora, RHEL, Alma, Rocky | dnf | Fedora 44 |
| Arch, Manjaro, EndeavourOS | pacman | Arch Linux |
| openSUSE | zypper | openSUSE Tumbleweed |

- CLI tools: distro packages.
- 1Password, Chrome, VS Code, GitHub CLI, Docker: vendor repos.
- Tailscale, Ollama, Starship, nvm, Claude Code: official install scripts.
- Other GUI apps: Flathub.

**WSL:** GUI apps off by default (`--gui` to include). Uses Docker Desktop's WSL integration if present. With 1Password on Windows, sets up git/ssh to use its SSH agent and commit signing via `op-ssh-sign-wsl.exe` (skip with `--skip 1password-ssh`).

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

Games, drivers and built-in OS apps are left out.

## Changing the list

- **Windows:** `$Apps` in `install.ps1` (`winget search <name>` for IDs)
- **macOS:** `MAC_FORMULAE`, `MAC_CASKS`, `MAC_APPSTORE` in `install.sh` (`mas search <name>` for IDs)
- **Linux:** `linux_main` in `install.sh`; Flathub apps are the `key|Name|app-id` list at its end

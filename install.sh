#!/usr/bin/env bash
# DeviceSetup: install my standard apps on macOS or Linux.
#
#   ./install.sh                 install everything for this OS
#   ./install.sh --dry-run       show what would be installed, change nothing
#   ./install.sh --list          print the app list for this OS
#   ./install.sh --skip steam,ollama
#   ./install.sh --no-gui        CLI tools only (default on WSL; use --gui to override)
#   ./install.sh --verbose       show installer output on screen (it always goes to the log)
#
# macOS uses Homebrew + the Mac App Store (mas).
# Linux detects the package manager (apt, dnf, pacman, zypper), uses it for CLI
# tools, vendor repos/installers where the vendor provides one, and Flathub for
# the rest of the GUI apps.
#
# Must stay compatible with macOS's bash 3.2: no associative arrays, no ${x,,}.

DRY_RUN=0
VERBOSE=0
LOG=/dev/null
GUI=""
SKIP=","
NODE_VERSION="lts/*"
NVM_VERSION="v0.40.3"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    --list|-l)    LIST_ONLY=1 ;;
    --no-gui)     GUI=0 ;;
    --gui)        GUI=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    --skip)       shift; SKIP=",$1," ;;
    --skip=*)     SKIP=",${1#--skip=}," ;;
    -h|--help)    usage ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# ---------- output ----------
if [ -t 1 ]; then
  B=$'\033[1;34m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'
else
  B=""; G=""; Y=""; R=""; D=""; N=""
fi
INSTALLED=(); SKIPPED=(); FAILED=(); NOTES=()

section() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
info()    { printf '    %s\n' "$*"; }
warn()    { printf '    %s! %s%s\n' "$Y" "$*" "$N"; }
note()    { NOTES+=("$*"); }

user_skipped() { case "$SKIP" in *",$1,"*) return 0 ;; esac; return 1; }

# item KEY LABEL CHECK INSTALL
#   CHECK and INSTALL are shell snippets. CHECK succeeding means "already installed".
item() {
  local key="$1" label="$2" check="$3" install="$4"
  if [ -n "$LIST_ONLY" ]; then printf '    %-26s %s%s%s\n' "$key" "$D" "$label" "$N"; return 0; fi
  if user_skipped "$key"; then
    SKIPPED+=("$label (--skip)"); printf '    %s- %s (skipped)%s\n' "$D" "$label" "$N"; return 0
  fi
  if eval "$check" >/dev/null 2>&1; then
    SKIPPED+=("$label (already installed)"); printf '    %s✓ %s (already installed)%s\n' "$D" "$label" "$N"; return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    INSTALLED+=("$label"); printf '    %s+ %s (would install)%s\n' "$G" "$label" "$N"; return 0
  fi
  printf '    %s+ Installing %s...%s\n' "$G" "$label" "$N"
  if run_logged "$install"; then
    INSTALLED+=("$label"); printf '    %s✓ %s%s\n' "$G" "$label" "$N"
  else
    FAILED+=("$label"); printf '    %s✗ %s failed. Last lines of output:%s\n' "$R" "$label" "$N"
    tail -n 12 "$TMPD/step.log" | sed 's/^/        /'
  fi
}

# Run a snippet. Its output goes to the log, and to the screen only with --verbose.
# sudo password prompts still show because sudo reads from /dev/tty.
run_logged() {
  local rc
  if [ "$VERBOSE" = 1 ]; then
    eval "$1" 2>&1 | tee "$TMPD/step.log"; rc=${PIPESTATUS[0]}
  else
    eval "$1" > "$TMPD/step.log" 2>&1 < /dev/null; rc=$?
  fi
  [ "$VERBOSE" = 0 ] && [ "$LOG" != /dev/null ] && cat "$TMPD/step.log" >> "$LOG"
  return $rc
}

# gui_item: same as item, but skipped when GUI apps are off
gui_item() {
  if [ "$GUI" = 0 ] && [ -z "$LIST_ONLY" ]; then
    SKIPPED+=("$2 (no GUI)"); printf '    %s- %s (GUI app, skipped)%s\n' "$D" "$2" "$N"; return 0
  fi
  item "$@"
}

has() { command -v "$1" >/dev/null 2>&1; }

TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t devicesetup)
trap 'rm -rf "$TMPD"' EXIT

# Common user-level bin dirs (Claude Code, pipx, etc.)
export PATH="$HOME/.local/bin:$PATH"

# ---------- Node via nvm (shared) ----------
load_nvm() {
  export NVM_DIR="$HOME/.nvm"
  if [ -s "$NVM_DIR/nvm.sh" ]; then . "$NVM_DIR/nvm.sh"
  elif has brew && [ -s "$(brew --prefix)/opt/nvm/nvm.sh" ]; then . "$(brew --prefix)/opt/nvm/nvm.sh"
  else return 1
  fi
}
node_installed() { load_nvm && [ "$(nvm version "$NODE_VERSION" 2>/dev/null)" != "N/A" ] && nvm exec default node --version; }
install_node() {
  load_nvm || return 1
  nvm install "$NODE_VERSION" && nvm alias default "$NODE_VERSION" && node --version
}
npm_global() { load_nvm && nvm use default >/dev/null 2>&1; npm install -g "$1"; }
npm_has()    { load_nvm && nvm use default >/dev/null 2>&1 && npm ls -g --depth=0 "$1" >/dev/null 2>&1; }

# =====================================================================
# macOS
# =====================================================================
MAC_FORMULAE="docker nvm mas"
MAC_CASKS="1password 1password-cli google-chrome obsidian raycast discord telegram spotify steam
tailscale-app syncthing-app moonlight remote-desktop-manager betterdisplay visual-studio-code warp
claude-code codex"
# Mac App Store: id|name (sign in to the App Store app first)
MAC_APPSTORE="1569813296|1Password for Safari
1444636541|Photomator
1295203466|Windows App
937984704|Amphetamine
1160435653|AutoMounter
497799835|Xcode"

ensure_clt() {
  xcode-select -p >/dev/null 2>&1 && return 0
  section "Xcode Command Line Tools"
  [ "$DRY_RUN" = 1 ] && { info "would run xcode-select --install"; return 0; }
  xcode-select --install >/dev/null 2>&1
  info "Finish the Command Line Tools installer window. Waiting..."
  until xcode-select -p >/dev/null 2>&1; do sleep 10; done
}

ensure_brew() {
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"
  fi
  if ! has brew; then
    section "Homebrew"
    [ "$DRY_RUN" = 1 ] && { info "would install Homebrew"; return 0; }
    # Ask for the password up front, then run unattended. stdin must not be our own script
    # (curl | bash), or the Homebrew installer would read it.
    sudo -v < /dev/tty || return 1
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null || return 1
    if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; else eval "$(/usr/local/bin/brew shellenv)"; fi
  fi
  if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
    [ "$DRY_RUN" = 1 ] || printf '\neval "$(%s shellenv)"\n' "$(command -v brew)" >> "$HOME/.zprofile"
  fi
}

# A cask counts as installed if brew manages it, or if its .app / binary is already there
# (apps installed by hand or from a vendor .dmg). That avoids brew's "already an App at" error.
cask_present() {
  brew list --cask "$1" >/dev/null 2>&1 && return 0
  local info line found=1
  info=$(brew info --cask "$1" 2>/dev/null) || return 1
  # Display name from the header, e.g. "==> tailscale-app (Tailscale): 1.2.3" (covers .pkg casks)
  line=$(printf '%s\n' "$info" | sed -n '1s/^==> [^ ]* (\(.*\)): .*/\1/p')
  [ -n "$line" ] && [ -e "/Applications/$line.app" ] && return 0
  while IFS= read -r line; do
    case "$line" in
      *" (App)")    line="${line% (App)}"
                    [ -e "/Applications/$line" ] || [ -e "$HOME/Applications/$line" ] && found=0 ;;
      *" (Binary)") line="${line% (Binary)}"; line="${line##*/}"
                    has "${line##* -> }" && found=0 ;;
    esac
  done <<EOF
$(printf '%s\n' "$info" | sed -n '/^==> Artifacts/,/^==> /p')
EOF
  return $found
}

# mas_present ID NAME: installed per mas, or the app bundle is already there
mas_present() {
  [ -d "/Applications/$2.app" ] && return 0
  has mas && mas list 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

slug() { echo "$1" | tr 'A-Z ' 'a-z-'; }

macos_main() {
  [ "$(id -u)" = 0 ] && { echo "Run as your normal user, not root (Homebrew refuses root)." >&2; exit 1; }
  [ -z "$LIST_ONLY" ] && { ensure_clt; ensure_brew || { echo "Homebrew install failed" >&2; exit 1; }; }

  section "Homebrew formulae"
  for f in $MAC_FORMULAE; do item "$f" "$f" "brew list --formula $f" "brew install $f"; done

  section "Homebrew casks"
  for c in $MAC_CASKS; do item "$c" "$c" "cask_present $c" "brew install --cask $c"; done

  section "Mac App Store"
  local id name
  while IFS='|' read -r id name; do
    [ -z "$id" ] && continue
    item "$(slug "$name")" "$name" "mas_present $id '$name'" "mas install $id || sudo mas install $id"
  done <<EOF
$MAC_APPSTORE
EOF

  section "Node.js (nvm)"
  if [ -z "$LIST_ONLY" ] && [ "$DRY_RUN" = 0 ] && has brew && brew list --formula nvm >/dev/null 2>&1; then
    mkdir -p "$HOME/.nvm"
    if ! grep -q 'NVM_DIR' "$HOME/.zshrc" 2>/dev/null; then
      cat >> "$HOME/.zshrc" <<'RC'

export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && \. "$(brew --prefix)/opt/nvm/nvm.sh"
RC
    fi
  fi
  item node "Node.js LTS (nvm)" node_installed install_node

  note "Mac App Store installs need you signed in to the App Store app."
  note "Docker from Homebrew is the CLI only. Use Docker Desktop, OrbStack or colima for the engine."
}

# =====================================================================
# Linux
# =====================================================================
detect_linux() {
  [ -r /etc/os-release ] && . /etc/os-release
  DISTRO="${PRETTY_NAME:-Linux}"
  local ids=" ${ID:-} ${ID_LIKE:-} "
  PM=""
  case "$ids" in
    *" debian "*|*" ubuntu "*)                  has apt-get && PM=apt ;;
    *" fedora "*|*" rhel "*|*" centos "*)       has dnf && PM=dnf ;;
    *" arch "*|*" archlinux "*)                 has pacman && PM=pacman ;;
    *" suse "*|*" opensuse "*|*opensuse-*)      has zypper && PM=zypper ;;
  esac
  # Unknown distro ID: fall back to whatever package manager exists
  if [ -z "$PM" ]; then
    for p in apt-get:apt dnf:dnf pacman:pacman zypper:zypper; do
      has "${p%%:*}" && { PM="${p##*:}"; break; }
    done
  fi
  [ -z "$PM" ] && { echo "Unsupported Linux distribution: $DISTRO (need apt, dnf, pacman or zypper)" >&2; exit 1; }

  ARCH=$(uname -m)
  case "$ARCH" in x86_64) DEB_ARCH=amd64 ;; aarch64|arm64) DEB_ARCH=arm64 ;; *) DEB_ARCH="$ARCH" ;; esac
  IS_WSL=0; grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1
  # On WSL, ignore Windows programs on PATH (/mnt/c/...) so they don't count as installed
  if [ "$IS_WSL" = 1 ]; then
    PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd: -)
  fi
  HAS_SYSTEMD=0; [ -d /run/systemd/system ] && HAS_SYSTEMD=1
  if [ -z "$GUI" ]; then
    if [ "$IS_WSL" = 1 ]; then GUI=0; else GUI=1; fi
  fi
}

pm_update() {
  case "$PM" in
    apt)    $SUDO apt-get update -q ;;
    dnf)    $SUDO dnf makecache -q ;;
    pacman) $SUDO pacman -Syu --noconfirm ;;
    zypper) $SUDO zypper -n refresh ;;
  esac
}

base_tools() {
  case "$PM" in
    apt)    pm_install curl ca-certificates gnupg unzip tar zstd || return 1
            # Ubuntu 24.04+: install the real ALSA lib first, otherwise apt can pick
            # liboss4-salsa-asound2 and then refuse to install Chrome and VS Code
            if [ "$GUI" = 1 ] && apt-cache show libasound2t64 >/dev/null 2>&1; then pm_install libasound2t64; fi ;;
    dnf)    pm_install curl ca-certificates gnupg2 unzip tar zstd libatomic ;;
    pacman) pm_install curl ca-certificates gnupg unzip tar zstd ;;
    zypper) pm_install curl ca-certificates gpg2 unzip tar gzip zstd libatomic1 ;;
  esac
}

pm_install() {
  case "$PM" in
    apt)    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" ;;
    dnf)    $SUDO dnf install -y -q "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper) $SUDO zypper -n --gpg-auto-import-keys install "$@" ;;
  esac
}

# Try each alternative in turn; "a+b" installs a and b together.
pm_install_any() {
  local alt
  for alt in "$@"; do
    pm_install $(echo "$alt" | tr '+' ' ') && return 0
  done
  return 1
}

fetch() { curl -fsSL --retry 3 "$1" -o "$2"; }

ensure_flathub() {
  [ -n "$FLATHUB_READY" ] && return 0
  has flatpak || pm_install flatpak || return 1
  $SUDO flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
  # Fedora ships a filtered Flathub; open it up
  $SUDO flatpak remote-modify --no-filter --enable flathub >/dev/null 2>&1
  FLATHUB_READY=1
}
flatpak_has()     { has flatpak && flatpak info "$1" >/dev/null 2>&1; }
flatpak_install() { ensure_flathub && $SUDO flatpak install -y --noninteractive --system flathub "$1"; }

rpm_import() { $SUDO rpm --import "$1"; }
rpm_repo() { # rpm_repo NAME BASEURL GPGKEY  (dnf and zypper read the same .repo format)
  local dir=/etc/yum.repos.d
  [ "$PM" = zypper ] && dir=/etc/zypp/repos.d
  printf '[%s]\nname=%s\nbaseurl=%s\nenabled=1\ngpgcheck=1\ntype=rpm-md\ngpgkey=%s\n' "$1" "$1" "$2" "$3" \
    | $SUDO tee "$dir/$1.repo" >/dev/null
}

# ----- vendor installers -----
install_gh() {
  case "$PM" in
    apt)
      $SUDO mkdir -p -m 755 /etc/apt/keyrings &&
      fetch https://cli.github.com/packages/githubcli-archive-keyring.gpg "$TMPD/gh.gpg" &&
      $SUDO install -m 644 "$TMPD/gh.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg &&
      echo "deb [arch=$DEB_ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null &&
      $SUDO apt-get update -q && pm_install gh ;;
    dnf)    pm_install gh || { rpm_repo gh-cli https://cli.github.com/packages/rpm https://cli.github.com/packages/rpm/gh-cli.repo.gpg && pm_install gh; } ;;
    pacman) pm_install github-cli ;;
    zypper) pm_install gh ;;
  esac
}

install_fastfetch() {
  pm_install fastfetch && return 0
  # Not packaged on older releases (e.g. Ubuntu 24.04, Debian 12): use the GitHub release
  local a="$DEB_ARCH"; [ "$a" = arm64 ] && a=aarch64
  local base=https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-$a
  case "$PM" in
    apt)        fetch "$base.deb" "$TMPD/fastfetch.deb" && pm_install "$TMPD/fastfetch.deb" ;;
    dnf|zypper) fetch "$base.rpm" "$TMPD/fastfetch.rpm" && $SUDO rpm -i "$TMPD/fastfetch.rpm" ;;
    *) return 1 ;;
  esac
}

onepassword_repo() {
  [ -n "$OP_REPO_READY" ] && return 0
  case "$PM" in
    apt)
      local pol=AC2D62742012EA22
      fetch https://downloads.1password.com/linux/keys/1password.asc "$TMPD/1p.asc" &&
      gpg --dearmor < "$TMPD/1p.asc" > "$TMPD/1p.gpg" &&
      $SUDO install -m 644 "$TMPD/1p.gpg" /usr/share/keyrings/1password-archive-keyring.gpg &&
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" \
        | $SUDO tee /etc/apt/sources.list.d/1password.list >/dev/null &&
      $SUDO mkdir -p /etc/debsig/policies/$pol /usr/share/debsig/keyrings/$pol &&
      fetch https://downloads.1password.com/linux/debian/debsig/1password.pol "$TMPD/1p.pol" &&
      $SUDO install -m 644 "$TMPD/1p.pol" /etc/debsig/policies/$pol/1password.pol &&
      $SUDO install -m 644 "$TMPD/1p.gpg" /usr/share/debsig/keyrings/$pol/debsig.gpg &&
      $SUDO apt-get update -q || return 1 ;;
    dnf|zypper)
      rpm_import https://downloads.1password.com/linux/keys/1password.asc &&
      rpm_repo 1password "https://downloads.1password.com/linux/rpm/stable/\$basearch" https://downloads.1password.com/linux/keys/1password.asc || return 1 ;;
    *) return 1 ;;
  esac
  OP_REPO_READY=1
}

install_1password() {
  if [ "$ARCH" = x86_64 ] && onepassword_repo; then pm_install 1password && return 0; fi
  # Arch, arm64, or repo failure: official tarball
  fetch "https://downloads.1password.com/linux/tar/stable/$ARCH/1password-latest.tar.gz" "$TMPD/1p.tar.gz" &&
  $SUDO mkdir -p /opt/1Password &&
  $SUDO tar -xzf "$TMPD/1p.tar.gz" --strip-components 1 -C /opt/1Password &&
  $SUDO /opt/1Password/after-install.sh
}

install_op_cli() {
  if [ "$ARCH" = x86_64 ] && onepassword_repo; then pm_install 1password-cli && return 0; fi
  local v
  v=$(curl -fsSL https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
  [ -n "$v" ] || return 1
  fetch "https://cache.agilebits.com/dist/1P/op2/pkg/v$v/op_linux_${DEB_ARCH}_v$v.zip" "$TMPD/op.zip" &&
  (cd "$TMPD" && unzip -oq op.zip op) &&
  $SUDO install -m 755 "$TMPD/op" /usr/local/bin/op
}

install_chrome() {
  if [ "$ARCH" = x86_64 ]; then
    case "$PM" in
      apt) fetch https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb "$TMPD/chrome.deb" &&
           pm_install "$TMPD/chrome.deb"; return ;;
      dnf|zypper)
           rpm_import https://dl.google.com/linux/linux_signing_key.pub &&
           fetch https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm "$TMPD/chrome.rpm" &&
           pm_install "$TMPD/chrome.rpm"; return ;;
    esac
  fi
  flatpak_install com.google.Chrome
}

install_vscode() {
  case "$PM" in
    apt)
      fetch https://packages.microsoft.com/keys/microsoft.asc "$TMPD/ms.asc" &&
      gpg --dearmor < "$TMPD/ms.asc" > "$TMPD/ms.gpg" &&
      $SUDO install -m 644 "$TMPD/ms.gpg" /usr/share/keyrings/microsoft.gpg &&
      echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | $SUDO tee /etc/apt/sources.list.d/vscode.list >/dev/null &&
      $SUDO apt-get update -q && pm_install code ;;
    dnf|zypper)
      rpm_import https://packages.microsoft.com/keys/microsoft.asc &&
      rpm_repo vscode https://packages.microsoft.com/yumrepos/vscode https://packages.microsoft.com/keys/microsoft.asc &&
      pm_install code ;;
    *) flatpak_install com.visualstudio.code ;;
  esac
}

install_docker() {
  case "$PM" in
    apt|dnf)
      fetch https://get.docker.com "$TMPD/get-docker.sh" && $SUDO sh "$TMPD/get-docker.sh" ||
        { [ "$PM" = apt ] && pm_install docker.io; } ||
        { [ "$PM" = dnf ] && pm_install moby-engine; } || return 1 ;;
    pacman) pm_install docker docker-compose docker-buildx || return 1 ;;
    zypper) pm_install docker docker-compose || return 1 ;;
  esac
  [ "$(id -u)" = 0 ] || $SUDO usermod -aG docker "$USER"
  [ "$HAS_SYSTEMD" = 1 ] && $SUDO systemctl enable --now docker
  note "Log out and back in so the docker group applies."
  return 0
}

install_nvm() {
  [ -s "$HOME/.nvm/nvm.sh" ] && return 0
  local v
  v=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
  fetch "https://raw.githubusercontent.com/nvm-sh/nvm/${v:-$NVM_VERSION}/install.sh" "$TMPD/nvm.sh" && bash "$TMPD/nvm.sh"
}

run_script() { # run_script URL [interpreter] [args...]
  local url="$1" sh="${2:-sh}"; shift; [ $# -gt 0 ] && shift
  fetch "$url" "$TMPD/script.sh" && "$sh" "$TMPD/script.sh" "$@"
}

linux_main() {
  detect_linux
  if [ "$(id -u)" = 0 ]; then
    SUDO=""
    [ -z "$LIST_ONLY" ] && warn "Running as root: per-user tools (nvm, Node, Claude Code) go to $HOME."
  else
    SUDO=sudo
    has sudo || { echo "sudo is required." >&2; exit 1; }
  fi

  section "System"
  info "$DISTRO ($ARCH), package manager: $PM$( [ "$IS_WSL" = 1 ] && echo ', WSL')"
  [ "$GUI" = 0 ] && info "GUI apps: off$( [ "$IS_WSL" = 1 ] && echo ' (WSL default, pass --gui to include them)')"

  if [ -z "$LIST_ONLY" ] && [ "$DRY_RUN" = 0 ]; then
    if [ -n "$SUDO" ]; then
      sudo -n true 2>/dev/null || sudo -v || exit 1
      ( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &
    fi
    section "Updating package lists and base tools"
    run_logged pm_update  || warn "Package list update failed (see log)"
    run_logged base_tools || warn "Some base tools failed to install (see log)"
  fi

  section "Command line tools"
  item git       "Git"        "has git"                 "pm_install git"
  item gh        "GitHub CLI" "has gh"                  "install_gh"
  item ripgrep   "ripgrep"    "has rg"                  "pm_install ripgrep"
  item btop      "btop"       "has btop"                "pm_install btop"
  item fastfetch "fastfetch"  "has fastfetch"           "install_fastfetch"
  item 7zip      "7-Zip"      "has 7z || has 7zz"       "pm_install_any 7zip p7zip-full p7zip+p7zip-plugins p7zip"
  item python    "Python 3 + pip" "has python3 && python3 -m pip --version" \
       "case $PM in pacman) pm_install python python-pip ;; apt) pm_install python3 python3-pip python3-venv ;; *) pm_install python3 python3-pip ;; esac"
  item syncthing "Syncthing"  "has syncthing"           "pm_install syncthing"
  item 1password-cli "1Password CLI" "has op"           "install_op_cli"
  item starship  "Starship"   "has starship"            "fetch https://starship.rs/install.sh \$TMPD/starship.sh && \$SUDO sh \$TMPD/starship.sh -y -b /usr/local/bin"

  section "Services"
  if [ "$IS_WSL" = 1 ] && [ -e "/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe" ]; then
    # Docker Desktop on the Windows side provides docker here through WSL integration
    item docker  "Docker (via Docker Desktop)" "true" "true"
    has docker || note "Turn on Docker Desktop > Settings > Resources > WSL integration for this distro."
  else
    item docker  "Docker"     "has docker"              "install_docker"
  fi
  item tailscale "Tailscale"  "has tailscale"           "run_script https://tailscale.com/install.sh"
  item ollama    "Ollama"     "has ollama"              "run_script https://ollama.com/install.sh"

  section "Development and AI"
  item nvm       "nvm"        "[ -s \"\$HOME/.nvm/nvm.sh\" ]" "install_nvm"
  item node      "Node.js LTS (nvm)" node_installed     install_node
  item claude-code "Claude Code" "has claude"           "run_script https://claude.ai/install.sh bash"
  item codex     "Codex CLI"  "npm_has @openai/codex"   "npm_global @openai/codex"
  item opencode  "OpenCode CLI" "npm_has @opencode/cli" "npm_global @opencode/cli"

  section "GUI apps"
  gui_item 1password       "1Password"          "has 1password || [ -x /opt/1Password/1password ]" install_1password
  gui_item google-chrome   "Google Chrome"      "has google-chrome-stable || flatpak_has com.google.Chrome" install_chrome
  gui_item visual-studio-code "Visual Studio Code" "has code || flatpak_has com.visualstudio.code" install_vscode
  local key label id
  while IFS='|' read -r key label id; do
    [ -z "$key" ] && continue
    gui_item "$key" "$label" "flatpak_has $id" "flatpak_install $id"
  done <<EOF
obsidian|Obsidian|md.obsidian.Obsidian
onlyoffice|ONLYOFFICE|org.onlyoffice.desktopeditors
discord|Discord|com.discordapp.Discord
telegram|Telegram|org.telegram.desktop
spotify|Spotify|com.spotify.Client
steam|Steam|com.valvesoftware.Steam
localsend|LocalSend|org.localsend.localsend_app
moonlight|Moonlight|com.moonlight_stream.Moonlight
parsec|Parsec|com.parsecgaming.parsec
android-studio|Android Studio|com.google.AndroidStudio
EOF

  note "Start Tailscale with: sudo tailscale up"
  note "Start Syncthing for your user with: systemctl --user enable --now syncthing"
  note "Enable Starship by adding 'eval \"\$(starship init bash)\"' to ~/.bashrc"
}

# =====================================================================
main() {
  case "$(uname -s)" in
    Darwin) OS=macOS ;;
    Linux)  OS=Linux ;;
    *) echo "Unsupported OS: $(uname -s). Use install.ps1 on Windows." >&2; exit 1 ;;
  esac

  if [ -n "$LIST_ONLY" ]; then
    printf '%sApps installed on %s%s\n' "$B" "$OS" "$N"
  else
    LOG="$HOME/devicesetup-$(date +%Y%m%d-%H%M%S).log"
    [ "$DRY_RUN" = 1 ] && LOG=/dev/null
    exec > >(tee -a "$LOG") 2>&1
    printf '%sDeviceSetup%s on %s%s\n' "$B" "$N" "$OS" "$( [ "$DRY_RUN" = 1 ] && echo ' (dry run)')"
  fi

  if [ "$OS" = macOS ]; then macos_main; else linux_main; fi
  [ -n "$LIST_ONLY" ] && exit 0

  section "Summary"
  local verb="Installed"; [ "$DRY_RUN" = 1 ] && verb="Would install"
  printf '    %s%s: %d%s\n' "$G" "$verb" "${#INSTALLED[@]}" "$N"
  [ ${#INSTALLED[@]} -gt 0 ] && printf '      %s\n' "${INSTALLED[@]}"
  printf '    %sSkipped: %d%s\n' "$D" "${#SKIPPED[@]}" "$N"
  if [ ${#FAILED[@]} -gt 0 ]; then
    printf '    %sFailed: %d%s\n' "$R" "${#FAILED[@]}" "$N"
    printf '      %s\n' "${FAILED[@]}"
  fi
  if [ "$DRY_RUN" = 0 ] && [ ${#NOTES[@]} -gt 0 ]; then
    section "Next steps"
    printf '    - %s\n' "${NOTES[@]}"
  fi
  [ "$DRY_RUN" = 0 ] && printf '\nLog: %s\n' "$LOG"
  [ ${#FAILED[@]} -eq 0 ]
}

main

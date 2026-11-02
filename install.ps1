<#
.SYNOPSIS
  DeviceSetup: install my standard apps on Windows with winget.

.EXAMPLE
  .\install.ps1                  # install everything
  .\install.ps1 -DryRun          # show what would be installed, change nothing
  .\install.ps1 -List            # print the app list
  .\install.ps1 -Skip Valve.Steam,Google.AndroidStudio

.NOTES
  Run from an elevated PowerShell so installers don't each ask for UAC.
  Works in Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$List,
  [string[]]$Skip = @()
)

# ---------- App list ----------
# winget IDs. Microsoft Store apps use their Store ID with Source 'msstore'.
# Also = other IDs that count as already installed (another channel or packaging of the same app).
$Apps = @(
  # Security & browsers
  @{ Id = 'AgileBits.1Password';         Name = '1Password' }
  @{ Id = 'Google.Chrome';               Name = 'Google Chrome'; Also = 'Google.Chrome.EXE','Google.Chrome.Beta','Google.Chrome.Beta.EXE','Google.Chrome.Dev' }
  # Productivity
  @{ Id = 'Obsidian.Obsidian';           Name = 'Obsidian' }
  @{ Id = 'Microsoft.PowerToys';         Name = 'PowerToys' }
  @{ Id = 'ONLYOFFICE.DesktopEditors';   Name = 'ONLYOFFICE' }
  @{ Id = 'Google.GoogleDrive';          Name = 'Google Drive' }
  # Communication
  @{ Id = 'Discord.Discord';             Name = 'Discord' }
  @{ Id = 'Telegram.TelegramDesktop';    Name = 'Telegram' }
  @{ Id = 'Microsoft.Teams';             Name = 'Microsoft Teams' }
  # Media
  @{ Id = 'Valve.Steam';                 Name = 'Steam' }
  # Networking & remote
  @{ Id = 'Tailscale.Tailscale';         Name = 'Tailscale' }
  @{ Id = 'Syncthing.Syncthing';         Name = 'Syncthing';     Also = 'BillStewart.SyncthingWindowsSetup','Martchus.syncthingtray' }
  @{ Id = 'LocalSend.LocalSend';         Name = 'LocalSend' }
  @{ Id = '9N7JSXC1SJK6';                Name = 'Blip';          Source = 'msstore' }
  @{ Id = 'ClassicOldSong.Apollo';       Name = 'Apollo' }
  @{ Id = 'Parsec.Parsec';               Name = 'Parsec' }
  # Utilities
  @{ Id = '7zip.7zip';                   Name = '7-Zip' }
  @{ Id = 'ShareX.ShareX';               Name = 'ShareX' }
  @{ Id = 'WinDirStat.WinDirStat';       Name = 'WinDirStat' }
  @{ Id = '9NP83LWLPZ9K';                Name = 'Apple Devices'; Source = 'msstore' }
  # Development
  @{ Id = 'Microsoft.VisualStudioCode';  Name = 'Visual Studio Code' }
  @{ Id = 'Microsoft.WindowsTerminal';   Name = 'Windows Terminal' }
  @{ Id = 'Microsoft.PowerShell';        Name = 'PowerShell 7' }
  @{ Id = 'Git.Git';                     Name = 'Git' }
  @{ Id = 'GitHub.cli';                  Name = 'GitHub CLI' }
  @{ Id = 'GitHub.GitHubDesktop';        Name = 'GitHub Desktop' }
  @{ Id = 'Docker.DockerDesktop';        Name = 'Docker Desktop' }
  @{ Id = 'OpenJS.NodeJS.LTS';           Name = 'Node.js LTS' }
  @{ Id = 'Python.Python.3.14';          Name = 'Python 3.14' }
  @{ Id = 'Python.Launcher';             Name = 'Python Launcher' }
  @{ Id = 'Google.AndroidStudio';        Name = 'Android Studio' }
  @{ Id = 'MSYS2.MSYS2';                 Name = 'MSYS2' }
  # AI
  @{ Id = 'Anthropic.Claude';            Name = 'Claude' }
  @{ Id = 'Anthropic.ClaudeCode';        Name = 'Claude Code' }
  @{ Id = 'OpenAI.Codex';                Name = 'Codex' }
  @{ Id = 'SST.OpenCodeDesktop';         Name = 'OpenCode Desktop' }
  @{ Id = 'Ollama.Ollama';               Name = 'Ollama' }
  # Terminal tools
  @{ Id = 'aristocratos.btop4win';       Name = 'btop' }
  @{ Id = 'Fastfetch-cli.Fastfetch';     Name = 'fastfetch' }
  @{ Id = 'BurntSushi.ripgrep.MSVC';     Name = 'ripgrep' }
  @{ Id = 'Starship.Starship';           Name = 'Starship' }
  @{ Id = 'JanDeDobbeleer.OhMyPosh';     Name = 'Oh My Posh' }
)
$NpmGlobals = @('@opencode/cli')
$WslDistro  = 'Ubuntu-24.04'

# ---------- helpers ----------
$Installed = New-Object System.Collections.Generic.List[string]
$Skipped   = New-Object System.Collections.Generic.List[string]
$Failed    = New-Object System.Collections.Generic.List[string]
$Notes     = New-Object System.Collections.Generic.List[string]

function Section($text) { Write-Host "`n==> $text" -ForegroundColor Blue }
function Say-Skip($name, $why) { $Skipped.Add("$name ($why)"); Write-Host "    - $name ($why)" -ForegroundColor DarkGray }
function Say-Ok($name)   { $Installed.Add($name); Write-Host "    + $name" -ForegroundColor Green }
function Say-Fail($name, $why) { $Failed.Add("$name ($why)"); Write-Host "    x $name failed: $why" -ForegroundColor Red }

function Test-UserSkipped($id, $name) {
  foreach ($s in $Skip) { if ($s -ieq $id -or $s -ieq $name) { return $true } }
  return $false
}

# winget exit codes that mean "nothing to do"
$AlreadyInstalledCodes = @(
  -1978335189,  # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
  -1978335135   # APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
)
$RebootCodes = @(
  -1978335215,  # APPINSTALLER_CLI_ERROR_INSTALL_REBOOT_REQUIRED_TO_FINISH
  -1978334967   # APPINSTALLER_CLI_ERROR_INSTALL_REBOOT_REQUIRED_FOR_INSTALL
)

function Test-WingetInstalled($app) {
  foreach ($id in @($app.Id) + @($app.Also | Where-Object { $_ })) {
    if (Test-WingetId $id $app.Source) { return $true }
  }
  return $false
}

function Test-WingetId($id, $source) {
  $wargs = @('list', '--id', $id, '--exact', '--accept-source-agreements', '--disable-interactivity')
  if ($source) { $wargs += @('--source', $source) }
  # Match on the ID in the output too: an exit code alone can be stale if winget fails to start
  $global:LASTEXITCODE = 1
  $out = & winget @wargs 2>&1 | Out-String
  return ($LASTEXITCODE -eq 0 -and $out -match [regex]::Escape($id))
}

function Install-WingetApp($app) {
  if (Test-UserSkipped $app.Id $app.Name) { Say-Skip $app.Name '-Skip'; return }
  if (Test-WingetInstalled $app) { Say-Skip $app.Name 'already installed'; return }
  if ($DryRun) { Say-Ok "$($app.Name) (would install)"; return }

  Write-Host "    Installing $($app.Name)..." -ForegroundColor Green
  $wargs = @('install', '--id', $app.Id, '--exact', '--silent',
            '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
  if ($app.Source) { $wargs += @('--source', $app.Source) } else { $wargs += @('--source', 'winget') }
  $global:LASTEXITCODE = 1
  & winget @wargs
  $code = $LASTEXITCODE
  if ($code -eq 0)                          { Say-Ok $app.Name }
  elseif ($AlreadyInstalledCodes -contains $code) { Say-Skip $app.Name 'already installed' }
  elseif ($RebootCodes -contains $code)     { Say-Ok "$($app.Name) (reboot to finish)"; $Notes.Add("Reboot to finish installing $($app.Name).") }
  else                                      { Say-Fail $app.Name ("winget exit code {0} (0x{0:X8})" -f $code) }
}

function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}

function Get-WslDistros {
  # wsl.exe prints UTF-16; WSL_UTF8 makes it plain UTF-8
  $env:WSL_UTF8 = '1'
  $out = & wsl.exe --list --quiet 2>$null
  if ($LASTEXITCODE -ne 0) { return @() }
  return @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

# ---------- main ----------
if ($List) {
  Write-Host 'Apps installed on Windows' -ForegroundColor Blue
  foreach ($a in $Apps) { '    {0,-30} {1}' -f $a.Id, $a.Name }
  '    {0,-30} {1}' -f "wsl $WslDistro", 'WSL + Ubuntu'
  foreach ($p in $NpmGlobals) { '    {0,-30} {1}' -f "npm $p", 'npm global' }
  return
}

$log = Join-Path $HOME ("devicesetup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
if (-not $DryRun) { Start-Transcript -Path $log -Append | Out-Null }

Write-Host ("DeviceSetup on Windows{0}" -f $(if ($DryRun) { ' (dry run)' } else { '' })) -ForegroundColor Blue

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host '    ! Not elevated: some installers will ask for UAC.' -ForegroundColor Yellow }

function Test-Winget {
  try { $global:LASTEXITCODE = 1; $null = & winget --version 2>&1; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

if (-not (Test-Winget) -and -not $DryRun) {
  # Fresh installs sometimes have App Installer present but not registered for this user yet
  Section 'Setting up winget'
  try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { }
  $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
  if (-not (Test-Winget)) {
    # Not installed at all (LTSC, Server, Windows Sandbox): install it with Microsoft's WinGet module
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
      Install-Module -Name Microsoft.WinGet.Client -Force -Scope CurrentUser -Repository PSGallery -AllowClobber | Out-Null
      Import-Module Microsoft.WinGet.Client
      if ($isAdmin) { Repair-WinGetPackageManager -AllUsers -Force -Latest } else { Repair-WinGetPackageManager -Force -Latest }
      try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { }
    } catch { Write-Host "    ! winget setup failed: $_" -ForegroundColor Yellow }
  }
}

if (-not (Test-Winget)) {
  Write-Host 'winget not found. Install "App Installer" from the Microsoft Store, then run this again.' -ForegroundColor Red
  if (-not $DryRun) { Stop-Transcript | Out-Null }
  exit 1
}

Section 'Apps (winget)'
foreach ($app in $Apps) { Install-WingetApp $app }
Update-SessionPath

Section 'WSL'
if (Test-UserSkipped 'wsl' $WslDistro) { Say-Skip "WSL $WslDistro" '-Skip' }
elseif ((Get-WslDistros) -contains $WslDistro) { Say-Skip "WSL $WslDistro" 'already installed' }
elseif ($DryRun) { Say-Ok "WSL $WslDistro (would install)" }
else {
  & wsl.exe --install -d $WslDistro --no-launch
  if ($LASTEXITCODE -eq 0) {
    Say-Ok "WSL $WslDistro"
    $Notes.Add("Open '$WslDistro' from the Start menu to create your Linux user (reboot first if WSL was just enabled).")
  } else { Say-Fail "WSL $WslDistro" "wsl exit code $LASTEXITCODE" }
}

Section 'npm globals'
foreach ($pkg in $NpmGlobals) {
  if (Test-UserSkipped $pkg $pkg) { Say-Skip $pkg '-Skip'; continue }
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    if ($DryRun) { Say-Ok "$pkg (would install after Node.js)" } else { Say-Fail $pkg 'npm not found (open a new terminal and run again)' }
    continue
  }
  $null = & npm ls -g --depth=0 $pkg 2>&1
  if ($LASTEXITCODE -eq 0) { Say-Skip $pkg 'already installed'; continue }
  if ($DryRun) { Say-Ok "$pkg (would install)"; continue }
  & npm install -g $pkg
  if ($LASTEXITCODE -eq 0) { Say-Ok $pkg } else { Say-Fail $pkg "npm exit code $LASTEXITCODE" }
}

Section 'Summary'
Write-Host ("    {0}: {1}" -f $(if ($DryRun) { 'Would install' } else { 'Installed' }), $Installed.Count) -ForegroundColor Green
$Installed | ForEach-Object { Write-Host "      $_" }
Write-Host ("    Skipped: {0}" -f $Skipped.Count) -ForegroundColor DarkGray
if ($Failed.Count) {
  Write-Host ("    Failed: {0}" -f $Failed.Count) -ForegroundColor Red
  $Failed | ForEach-Object { Write-Host "      $_" }
}
if ($Notes.Count) {
  Section 'Next steps'
  $Notes | ForEach-Object { Write-Host "    - $_" }
}
if (-not $DryRun) { Stop-Transcript | Out-Null; Write-Host "`nLog: $log" }
if ($Failed.Count) { exit 1 }

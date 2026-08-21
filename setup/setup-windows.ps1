<#
  Kingo classroom — Windows bootstrap. Its ONLY job is to turn on WSL2 and
  install Ubuntu. Everything else (Podman, the stack) runs INSIDE that Ubuntu
  with the bash setup — same Linux runtime as Mac/Linux/CI, one CLI, no drift.

  Run it (right-click -> "Run with PowerShell"; it self-elevates):
    powershell -ExecutionPolicy Bypass -File setup\setup-windows.ps1

  RE-RUNNABLE: enabling WSL2 can force a reboot — just run it again afterwards.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!! $m" -ForegroundColor Yellow }

# Elevate (enabling WSL2 needs Administrator).
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
  Say "Elevating to Administrator (approve the prompt) ..."
  Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
  return
}

function Test-WslReady { try { wsl --status *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false } }

if (Test-WslReady) {
  Say "WSL2 is already enabled."
} else {
  Say "Enabling WSL2 and installing Ubuntu (this may require ONE reboot) ..."
  # Installs the WSL2 kernel + the 'Virtual Machine Platform' feature and the
  # default Ubuntu distro.
  wsl --install
  wsl --set-default-version 2 *> $null
  if (-not (Test-WslReady)) {
    Warn "WSL2 was just enabled and needs a RESTART to finish."
    Warn "Please REBOOT your PC, then run this script again."
    Read-Host "Press Enter to close"
    return
  }
}

Say "WSL2 is ready. Two more steps — see docs\STUDENT-GUIDE-WINDOWS.md:"
Write-Host ""
Write-Host "  1) Open the 'Ubuntu' app from the Start menu. On first launch it asks you" -ForegroundColor White
Write-Host "     to choose a Linux username and password (the password stays invisible" -ForegroundColor White
Write-Host "     while you type — that is normal)." -ForegroundColor White
Write-Host ""
Write-Host "  2) In that Ubuntu terminal, paste this block and press Enter:" -ForegroundColor White
Write-Host ""
Write-Host "       sudo apt update && sudo apt install -y git" -ForegroundColor Green
Write-Host "       git clone https://github.com/frankhuettner/kingo-pod.git" -ForegroundColor Green
Write-Host "       cd kingo-pod && bash setup/setup-linux.sh" -ForegroundColor Green
Write-Host ""
Write-Host "  That installs Podman and starts the class stack. Open the services in your" -ForegroundColor White
Write-Host "  normal Windows browser at http://localhost:<port>." -ForegroundColor White
Read-Host "`nPress Enter to close"

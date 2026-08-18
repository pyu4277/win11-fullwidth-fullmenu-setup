#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 post-format setup tweaks.

.DESCRIPTION
    Self-contained bootstrap script. Needs nothing but Windows PowerShell 5.1,
    which ships with Windows. No admin rights, no git, no cloning required.
    Every tweak is idempotent and can be undone with -Revert.

    Messages are intentionally ASCII-only: this machine's ANSI code page is 949
    while consoles run 65001, and a non-BOM UTF-8 script with Korean text would
    be mis-decoded by Windows PowerShell 5.1. Korean documentation lives in
    README.md instead.

.PARAMETER List
    Show every tweak with its current state, then exit.

.PARAMETER Only
    Apply only the named tweaks, comma separated.

.PARAMETER All
    Apply every tweak without prompting.

.PARAMETER Revert
    Undo instead of apply.

.EXAMPLE
    irm https://raw.githubusercontent.com/pyu4277/win11-fullwidth-fullmenu-setup/main/setup.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/pyu4277/win11-fullwidth-fullmenu-setup/main/setup.ps1))) -All

.EXAMPLE
    .\setup.ps1 -Only classic-context-menu
#>
param(
    [string[]]$Only,
    [switch]$All,
    [switch]$Revert,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- constants

# Windows 11 modern context menu handler. An empty InprocServer32 default
# value disables it, which brings back the full Windows 10 style menu.
$ClassicMenuKey = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'

# Hancom IME. Typing "?" under it yields the FULL-WIDTH question mark U+FF1F,
# which is A3 BF in CP949; read back as Latin-1 the trailing BF renders as an
# inverted question mark. Win+Space kept toggling into it, so the symptom
# looked random. Removing the input method removes both the source and the
# thing Win+Space had to switch to.
$HancomClsid = '{1BB25C39-E526-4F83-BDCB-3FA5CAA7F8FE}'
$HancomTip   = '0412:{1BB25C39-E526-4F83-BDCB-3FA5CAA7F8FE}{B337C844-9834-4A13-92C8-0B63C82E11D4}'
$HancomDll   = Join-Path $env:SystemRoot 'HancomIME\x86\HCHangulIME.dll'

# ---------------------------------------------------------------- helpers

function Write-Step  { param([string]$Message) Write-Host "  $Message" }
function Write-Good  { param([string]$Message) Write-Host "  $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "  $Message" -ForegroundColor Yellow }

function Restart-Explorer {
    Write-Step 'Restarting Explorer (taskbar blinks for a moment)...'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
        Start-Sleep -Seconds 2
    }
}

function Get-HancomTips {
    param($Language)
    @($Language.InputMethodTips | Where-Object { $_ -like "*$HancomClsid*" })
}

# ---------------------------------------------------------------- tweaks

$Tweaks = @(
    [pscustomobject]@{
        Name  = 'classic-context-menu'
        Title = 'Full right-click menu, no "Show more options" step'
        Test  = {
            Test-Path "$ClassicMenuKey\InprocServer32"
        }
        Apply = {
            $sub = "$ClassicMenuKey\InprocServer32"
            New-Item -Path $sub -Force | Out-Null
            # The default value must exist AND be an empty string.
            Set-ItemProperty -Path $sub -Name '(default)' -Value '' -Type String -Force
            Restart-Explorer
            Write-Good 'Classic context menu enabled.'
        }
        Revert = {
            if (Test-Path $ClassicMenuKey) {
                Remove-Item -Path $ClassicMenuKey -Recurse -Force
                Restart-Explorer
                Write-Good 'Windows 11 modern context menu restored.'
            } else {
                Write-Step 'Already using the modern menu; nothing to do.'
            }
        }
    },

    [pscustomobject]@{
        Name  = 'remove-hancom-ime'
        Title = 'Remove Hancom IME (stops full-width "?" turning into an inverted one)'
        Test  = {
            $found = $false
            foreach ($lang in (Get-WinUserLanguageList)) {
                if ((Get-HancomTips $lang).Count -gt 0) { $found = $true }
            }
            -not $found
        }
        Apply = {
            $list = Get-WinUserLanguageList
            $changed = $false
            foreach ($lang in $list) {
                $bad = Get-HancomTips $lang
                if ($bad.Count -eq 0) { continue }
                $keep = @($lang.InputMethodTips | Where-Object { $_ -notlike "*$HancomClsid*" })
                if ($keep.Count -eq 0) {
                    throw "Refusing to continue: removing Hancom IME would leave '$($lang.LanguageTag)' with no input method at all."
                }
                $lang.InputMethodTips.Clear()
                foreach ($tip in $keep) { [void]$lang.InputMethodTips.Add($tip) }
                $changed = $true
            }
            if ($changed) {
                Set-WinUserLanguageList -LanguageList $list -Force
                Write-Good 'Hancom IME removed. Win+Space now has nothing to switch to.'
                Write-Step 'Sign out and back in for every running app to pick this up.'
            } else {
                Write-Step 'Hancom IME is not registered; nothing to do.'
            }
        }
        Revert = {
            if (-not (Test-Path $HancomDll)) {
                throw "Hancom IME is not installed on this machine ($HancomDll missing). Reinstall Hancom Office first."
            }
            $list = Get-WinUserLanguageList
            $ko = $list | Where-Object { $_.LanguageTag -like 'ko*' } | Select-Object -First 1
            if (-not $ko) { throw 'Korean is not in the language list; add it in Settings first.' }
            if ($ko.InputMethodTips -contains $HancomTip) {
                Write-Step 'Hancom IME is already registered; nothing to do.'
            } else {
                [void]$ko.InputMethodTips.Add($HancomTip)
                Set-WinUserLanguageList -LanguageList $list -Force
                Write-Good 'Hancom IME restored.'
            }
        }
    }
)

# ---------------------------------------------------------------- engine

function Get-State {
    param($Tweak)
    try {
        if (& $Tweak.Test) { 'APPLIED' } else { 'not applied' }
    } catch {
        'unknown'
    }
}

function Show-Table {
    Write-Host ''
    Write-Host 'Available tweaks:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $Tweaks.Count; $i++) {
        $t = $Tweaks[$i]
        $state = Get-State $t
        $color = if ($state -eq 'APPLIED') { 'Green' } else { 'Gray' }
        Write-Host ("  [{0}] {1,-22} {2}" -f ($i + 1), $t.Name, $t.Title)
        Write-Host ("      current state: {0}" -f $state) -ForegroundColor $color
    }
    Write-Host ''
}

function Invoke-Tweak {
    param($Tweak, [bool]$DoRevert)
    $verb = if ($DoRevert) { 'Reverting' } else { 'Applying' }
    Write-Host ''
    Write-Host "$verb : $($Tweak.Name)" -ForegroundColor Cyan
    try {
        if ($DoRevert) { & $Tweak.Revert } else { & $Tweak.Apply }
    } catch {
        Write-Warn2 "Failed: $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host '=== Windows 11 post-format setup ===' -ForegroundColor Cyan
Write-Host 'No admin rights needed. Nothing here touches system files.'

if ($List) { Show-Table; return }

$selected = @()

if ($All) {
    $selected = $Tweaks
} elseif ($Only) {
    foreach ($name in $Only) {
        $match = $Tweaks | Where-Object { $_.Name -eq $name }
        if ($match) { $selected += $match }
        else { Write-Warn2 "Unknown tweak: $name" }
    }
} else {
    Show-Table
    $verb = if ($Revert) { 'revert' } else { 'apply' }
    Write-Host "Enter numbers to $verb (e.g. 1,2), 'a' for all, or 'q' to quit: " -NoNewline
    $answer = Read-Host
    switch -Regex ($answer.Trim().ToLower()) {
        '^q' { Write-Host 'Cancelled.'; return }
        '^a' { $selected = $Tweaks }
        default {
            foreach ($piece in $answer -split '[,\s]+') {
                if ($piece -match '^\d+$') {
                    $idx = [int]$piece - 1
                    if ($idx -ge 0 -and $idx -lt $Tweaks.Count) { $selected += $Tweaks[$idx] }
                    else { Write-Warn2 "Out of range: $piece" }
                }
            }
        }
    }
}

if (-not $selected -or $selected.Count -eq 0) {
    Write-Host 'Nothing selected.'
    return
}

foreach ($tweak in $selected) { Invoke-Tweak -Tweak $tweak -DoRevert:$Revert }

Write-Host ''
Write-Host 'Done. Final state:' -ForegroundColor Cyan
foreach ($t in $Tweaks) {
    Write-Host ("  {0,-22} {1}" -f $t.Name, (Get-State $t))
}
Write-Host ''

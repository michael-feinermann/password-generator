param(
    [string]$InstalledExecutable = (Join-Path $env:LOCALAPPDATA 'Programs\Password Generator 2.3.6\PasswordGenerator.exe'),
    [switch]$AllUsers
)
$ErrorActionPreference = 'Stop'
$target = (Resolve-Path -LiteralPath $InstalledExecutable).Path
if ([IO.Path]::GetFileName($target) -ne 'PasswordGenerator.exe' -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Unexpected application executable.' }
$programs = [Environment]::GetFolderPath($(if ($AllUsers) { 'CommonPrograms' } else { 'Programs' }))
if (-not (Test-Path -LiteralPath $programs -PathType Container)) { throw 'Start menu Programs folder is unavailable.' }
$shortcutPath = Join-Path $programs 'Password Generator.lnk'
$shell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $shortcutPath) {
    if (((Get-Item -LiteralPath $shortcutPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Start menu entry must not be a reparse point.' }
    $existing = $shell.CreateShortcut($shortcutPath)
    if (-not $existing.TargetPath.Equals($target, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'An unrelated Start menu entry already uses this name.'
    }
}
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = [IO.Path]::GetDirectoryName($target)
$shortcut.IconLocation = $target + ',0'
$shortcut.Description = 'Password Generator 2.3.6'
$shortcut.WindowStyle = 1
$shortcut.Save()
$saved = $shell.CreateShortcut($shortcutPath)
if (-not $saved.TargetPath.Equals($target, [StringComparison]::OrdinalIgnoreCase)) { throw 'Start menu shortcut verification failed.' }
Write-Output "Registered: $shortcutPath"

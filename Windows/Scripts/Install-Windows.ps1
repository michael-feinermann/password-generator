param([Parameter(Mandatory)][string]$PackageDirectory,
      [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\Password Generator 2.3.6'),
      [switch]$AllUsersStartMenu)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
$package = (Resolve-Path -LiteralPath $PackageDirectory).Path
$target = [IO.Path]::GetFullPath($InstallDirectory)
$programs = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs'))
if (-not $target.StartsWith($programs + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Install target must be inside the current user LocalAppData\Programs directory.' }
if ($target.StartsWith($package + '\', [StringComparison]::OrdinalIgnoreCase) -or $target.Equals($package, [StringComparison]::OrdinalIgnoreCase)) { throw 'Install target cannot be inside the source package.' }
$ancestor = [IO.DirectoryInfo]::new($target).Parent
while ($null -ne $ancestor) {
    if ($ancestor.Exists -and (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Install target ancestors cannot be reparse points.' }
    $ancestor = $ancestor.Parent
}
if (Test-Path -LiteralPath $target) { throw 'Install target already exists; refusing to overwrite an existing installation.' }
& $dotnet run --project (Join-Path $repo 'Windows\PasswordGenerator.Signing') -c Release -- verify $package
if ($LASTEXITCODE -ne 0) { throw 'Package verification rejected installation.' }
New-Item -ItemType Directory -Path $target | Out-Null
try {
    Get-ChildItem -LiteralPath $package -Force | Copy-Item -Destination $target -Recurse -Force
    & $dotnet run --project (Join-Path $repo 'Windows\PasswordGenerator.Signing') -c Release -- verify $target
    if ($LASTEXITCODE -ne 0) { throw 'Installed inventory verification failed.' }
    & (Join-Path $PSScriptRoot 'Register-StartMenu.ps1') -InstalledExecutable (Join-Path $target 'PasswordGenerator.exe') -AllUsers:$AllUsersStartMenu
    Write-Output "Installed and verified: $target"
} catch { throw "Installation was not completed: $($_.Exception.Message). Partial files are preserved for inspection at $target" }

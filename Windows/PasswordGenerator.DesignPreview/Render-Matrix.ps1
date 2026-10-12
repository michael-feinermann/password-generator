param([string] $OutputDirectory = "Windows/artifacts/design-review")
$ErrorActionPreference = 'Stop'
$dotnet = Join-Path $env:ProgramFiles 'dotnet/dotnet.exe'
$project = Join-Path $PSScriptRoot 'PasswordGenerator.DesignPreview.csproj'
& $dotnet build $project -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'Design preview build failed.' }
$dll = Join-Path $PSScriptRoot 'bin/Release/net10.0-windows/PasswordGenerator.DesignPreview.dll'
& $dotnet $dll --matrix $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Offscreen design checks failed. Inspect per-scene JSON files.' }
Write-Output 'Offscreen design checks passed for 120 scenes.'

param([switch]$Publish, [string]$KeyDirectory = 'A:\Passoword Generator Keys')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
function Run-Dotnet { & $dotnet @args; if ($LASTEXITCODE -ne 0) { throw "dotnet failed ($LASTEXITCODE)" } }
Push-Location -LiteralPath $repo
try {
    Run-Dotnet run --project Windows/PasswordGenerator.Tests -c Release
    Run-Dotnet run --project Windows/PasswordGenerator.App.Tests -c Release
    Run-Dotnet run --project Windows/PasswordGenerator.Security.Tests -c Release
    Run-Dotnet build Windows/PasswordGenerator.App -c Release
    if ($Publish) {
        $output = Join-Path $repo 'Windows\artifacts\app'
        if (Test-Path -LiteralPath $output) { throw 'Publish output exists; use a fresh workspace or archive it before publishing.' }
        Run-Dotnet publish Windows/PasswordGenerator.App -c Release -r win-x64 --self-contained true -o $output -p:DebugType=None -p:DebugSymbols=false
        $notices = Join-Path $output 'Notices'
        $runtime = Get-ChildItem (Join-Path $env:USERPROFILE '.nuget\packages\microsoft.netcore.app.runtime.win-x64') -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1
        if ($null -eq $runtime) { throw 'Missing .NET runtime distribution notices.' }
        Copy-Item -LiteralPath (Join-Path $runtime.FullName 'LICENSE.TXT') -Destination (Join-Path $notices 'dotnet-LICENSE.TXT')
        Copy-Item -LiteralPath (Join-Path $runtime.FullName 'THIRD-PARTY-NOTICES.TXT') -Destination (Join-Path $notices 'dotnet-THIRD-PARTY-NOTICES.TXT')
        Run-Dotnet run --project Windows/PasswordGenerator.Signing -c Release -- sign $KeyDirectory $output
        Run-Dotnet run --project Windows/PasswordGenerator.Signing -c Release -- verify $output
        $archive = Join-Path $repo 'Windows\artifacts\Password.Generator-2.3.6-Windows-x64.zip'
        Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $output | Select-Object -ExpandProperty FullName) -DestinationPath $archive
        Run-Dotnet run --project Windows/PasswordGenerator.Signing -c Release -- sign-file $KeyDirectory $archive
        Get-FileHash -LiteralPath $archive -Algorithm SHA256 | ConvertTo-Json | Set-Content -LiteralPath ($archive + '.sha256.json') -Encoding utf8
    }
} finally { Pop-Location }

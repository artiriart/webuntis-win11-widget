# Publishes an unsigned MSIX. Signing stays on the developer's computer.
# This script must not create or upload a certificate or private key.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$artifactDir = Join-Path $repoRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

dotnet publish (Join-Path $repoRoot 'src\WebUntis.App\WebUntis.App.csproj') `
    -c Release `
    -p:Platform=x64 `
    -p:RuntimeIdentifier=win-x64 `
    -p:WindowsAppSDKSelfContained=true `
    -p:AppxPackageSigningEnabled=false `
    -p:GenerateAppxPackageOnBuild=true `
    -bl:(Join-Path $repoRoot 'build.binlog')
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

$package = Get-ChildItem -Path (Join-Path $repoRoot 'src\WebUntis.App') -Recurse -Filter '*.msix' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $package) {
    throw 'No MSIX was produced.'
}

$unsignedPackage = Join-Path $artifactDir 'WebUntis.msix'
Copy-Item $package.FullName $unsignedPackage -Force

$signature = Get-AuthenticodeSignature $unsignedPackage
if ($signature.Status -ne 'NotSigned') {
    throw "Expected an unsigned package, but the signature status was $($signature.Status)."
}

$privateMaterial = Get-ChildItem -Path $artifactDir -Include '*.pfx', '*.pvk', '*.cer' -Recurse -File -ErrorAction SilentlyContinue
if ($privateMaterial) {
    throw 'Certificate material must not be uploaded with the unsigned package.'
}

Copy-Item (Join-Path $repoRoot 'docs\install-windows.md') (Join-Path $artifactDir 'INSTALL.md') -Force
Write-Host "Unsigned package: $unsignedPackage"

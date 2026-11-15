# Creates a development signing certificate in the current user's store, publishes
# the MSIX with that certificate, and exports only the public .cer file.
# The private key is never written to a PFX and must not be uploaded.

$ErrorActionPreference = 'Stop'

$subject = 'CN=artiriart'
$repoRoot = Split-Path -Parent $PSScriptRoot
$artifactDir = Join-Path $repoRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

$certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $subject `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -FriendlyName 'WebUntis development' `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(1)

if ($certificate.Subject -ne $subject) {
    throw "Certificate subject '$($certificate.Subject)' does not match package publisher $subject."
}

$publicCertificate = Join-Path $artifactDir 'WebUntis.cer'
Export-Certificate -Cert $certificate -FilePath $publicCertificate | Out-Null

Write-Host "Signing with certificate thumbprint $($certificate.Thumbprint)."

dotnet publish (Join-Path $repoRoot 'src\WebUntis.App\WebUntis.App.csproj') `
    -c Release `
    -p:Platform=x64 `
    -p:RuntimeIdentifier=win-x64 `
    -p:WindowsAppSDKSelfContained=true `
    -p:PackageCertificateThumbprint=$($certificate.Thumbprint) `
    -p:AppxPackageSigningEnabled=true `
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

$signedPackage = Join-Path $artifactDir 'WebUntis.msix'
Copy-Item $package.FullName $signedPackage -Force

$privateMaterial = Get-ChildItem -Path $artifactDir -Include '*.pfx', '*.pvk' -Recurse -File -ErrorAction SilentlyContinue
if ($privateMaterial) {
    throw 'Private key material was written next to the package and will not be uploaded.'
}

Import-Certificate -FilePath $publicCertificate -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' | Out-Null
Import-Certificate -FilePath $publicCertificate -CertStoreLocation 'Cert:\CurrentUser\Root' | Out-Null

$signTool = Get-ChildItem -Path 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter 'signtool.exe' |
    Where-Object { $_.FullName -match '\\x64\\signtool.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $signTool) {
    throw 'signtool.exe was not found.'
}

& $signTool.FullName verify /pa $signedPackage
if ($LASTEXITCODE -ne 0) {
    throw "The MSIX signature did not verify. signtool exit code $LASTEXITCODE."
}

Copy-Item (Join-Path $repoRoot 'docs\install-windows.md') (Join-Path $artifactDir 'INSTALL.md') -Force
Write-Host "Signed package: $signedPackage"

# Signs an unsigned WebUntis MSIX with a certificate created on this computer.
# The private key stays in Cert:\CurrentUser\My. This script does not upload it.

param(
    [Parameter(Mandatory = $true)]
    [string]$Package
)

$ErrorActionPreference = 'Stop'
$subject = 'CN=artiriart'
$packagePath = (Resolve-Path $Package).Path
$outDir = Split-Path -Parent $packagePath
$signedPackage = Join-Path $outDir 'WebUntis.signed.msix'

$certificate = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $subject -and $_.FriendlyName -eq 'WebUntis development' -and $_.HasPrivateKey } |
    Select-Object -First 1

if (-not $certificate) {
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
}

if ($certificate.Subject -ne $subject) {
    throw "Certificate subject '$($certificate.Subject)' must match the package publisher $subject."
}

$publicCertificate = Join-Path $outDir 'WebUntis.cer'
Export-Certificate -Cert $certificate -FilePath $publicCertificate | Out-Null
Copy-Item $packagePath $signedPackage -Force

$signTool = Get-ChildItem -Path 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\signtool.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $signTool) {
    throw 'signtool.exe was not found. Install the Windows SDK Signing Tools for Desktop Apps.'
}

& $signTool.FullName sign /fd SHA256 /sha1 $certificate.Thumbprint /tr http://timestamp.digicert.com /td SHA256 $signedPackage
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Timestamp server was unavailable. Signing without a timestamp.'
    & $signTool.FullName sign /fd SHA256 /sha1 $certificate.Thumbprint $signedPackage
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed with exit code $LASTEXITCODE."
    }
}

Write-Host ''
Write-Host "Signed package: $signedPackage"
Write-Host "Public certificate: $publicCertificate"
Write-Host 'The private key remains in Cert:\CurrentUser\My and was not exported.'
Write-Host ''
Write-Host 'From an administrator PowerShell window, trust the certificate and install:'
Write-Host "  Import-Certificate -FilePath `"$publicCertificate`" -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
Write-Host "  Import-Certificate -FilePath `"$publicCertificate`" -CertStoreLocation Cert:\LocalMachine\Root"
Write-Host "  Add-AppxPackage -Path `"$signedPackage`""

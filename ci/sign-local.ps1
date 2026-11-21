# Signs an unsigned WebUntis MSIX with a certificate created on this computer.
# The private key stays in Cert:\CurrentUser\My. This script does not upload it.

param(
    [Parameter(Mandatory = $true)]
    [string]$Package,
    [string]$Pfx
)

$ErrorActionPreference = 'Stop'
$subject = 'CN=artiriart'
$packagePath = (Resolve-Path $Package).Path
$outDir = Split-Path -Parent $packagePath
$signablePackage = Join-Path $outDir 'WebUntis.signable.msix'
$signedPackage = Join-Path $outDir 'WebUntis.signed.msix'
. (Join-Path $PSScriptRoot 'repack-signable.ps1')
Convert-ToSignableMsix -InputPackage $packagePath -OutputPackage $signablePackage

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
$signTool = Get-WindowsSdkTool 'signtool.exe'
Copy-Item $signablePackage $signedPackage -Force

if ($Pfx) {
    $pfxPath = (Resolve-Path $Pfx).Path
    $securePassword = Read-Host -AsSecureString 'PFX password'
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try {
        $pfxPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
        $loaded = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxPath, $pfxPassword)
        if ($loaded.Subject -ne $subject) {
            throw "PFX subject is '$($loaded.Subject)'. It must be exactly $subject, matching the package publisher."
        }
        Export-Certificate -Cert $loaded -FilePath $publicCertificate | Out-Null
        & $signTool sign /fd SHA256 /f $pfxPath /p $pfxPassword $signedPackage
        if ($LASTEXITCODE -ne 0) {
            throw "signtool failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        $pfxPassword = $null
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
}
else {
    Export-Certificate -Cert $certificate -FilePath $publicCertificate | Out-Null
    & $signTool sign /fd SHA256 /sha1 $certificate.Thumbprint $signedPackage
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

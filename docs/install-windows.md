# Test the package on your PC

CI publishes an unsigned MSIX. Azure Trusted Signing is only needed later, when other people should install the app without trusting a certificate you made. It is not required to test on your own Windows 11 PC.

Download the `webuntis-msix` artifact from a successful run of `.github/workflows/build.yml` and unzip it. You should see `WebUntis.msix` and this file. There is no certificate in that zip.

The package publisher is `CN=artiriart`. A local signing certificate must use that exact subject.

## Fastest test: install the unsigned package

Developer Mode is already enabled, so Windows can sideload this package without a signature.

Open PowerShell in the unzipped folder:

```powershell
Add-AppxPackage -Path .\WebUntis.msix -AllowUnsigned
```

Open WebUntis from the Start menu. The window should say that you are not signed in. The widget can appear in the Widgets Board only after the package is installed.

## If signtool says the file format is not recognized

The package is Zip64. `signtool` cannot sign that format, and current `makeappx.exe` writes Zip64 too. From a checkout of this branch, rewrite it before signing:

```powershell
. .\ci\repack-signable.ps1
Convert-ToSignableMsix -InputPackage .\WebUntis.msix -OutputPackage .\WebUntis.signable.msix
& "C:\Program Files (x86)\Windows Kits\10\bin\10.0.28000.0\x64\signtool.exe" sign /fd SHA256 /f .\WebUntis.pfx /p (Read-Host 'PFX password') .\WebUntis.signable.msix
```

The PFX subject must be exactly `CN=artiriart`. Do not commit the PFX. New CI artifacts are rewritten before upload.

## Sign it on this computer

This checks the signed-install path. The private key is created in your user certificate store and is not written to a file.

From the repository, in PowerShell:

```powershell
.\ci\sign-local.ps1 -Package C:\path\to\WebUntis.msix
```

The script needs `signtool.exe` from the Windows SDK Signing Tools. It writes two files next to the unsigned package:

- `WebUntis.signed.msix`
- `WebUntis.cer`, the public certificate only

Then open PowerShell as administrator:

```powershell
Import-Certificate -FilePath .\WebUntis.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
Import-Certificate -FilePath .\WebUntis.cer -CertStoreLocation Cert:\LocalMachine\Root
Add-AppxPackage -Path .\WebUntis.signed.msix
```

Trusted People is the sideload signer store. Trusted Root is also required because the certificate is self-signed. Do not use that certificate for anything else.

If signing fails because the publisher does not match, do not change the certificate subject. The package was built for `CN=artiriart`.

## Remove it

```powershell
Get-AppxPackage artiriart.WebUntis | Remove-AppxPackage
Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Subject -eq 'CN=artiriart' -and $_.FriendlyName -eq 'WebUntis development' } | Remove-Item
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -eq 'CN=artiriart' -and $_.FriendlyName -eq 'WebUntis development' } | Remove-Item
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=artiriart' -and $_.FriendlyName -eq 'WebUntis development' } | Remove-Item
```

The LocalMachine commands need an administrator PowerShell.

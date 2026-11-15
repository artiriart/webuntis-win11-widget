# Install a development build

The GitHub Actions artifact contains three files:

- `WebUntis.msix`, signed by that run's development certificate
- `WebUntis.cer`, the public certificate only
- `INSTALL.md`, this page

The private key is created in the Actions runner's certificate store and is not in the artifact or the repository. A certificate from one run will not install a package from another run. Use the `.cer` from the same zip as the `.msix`.

Developer Mode lets Windows sideload a package. It does not trust this certificate. You still have to install `WebUntis.cer`.

## Trust the certificate

Open PowerShell as administrator in the unzipped artifact folder and run:

```powershell
Import-Certificate -FilePath .\WebUntis.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
Import-Certificate -FilePath .\WebUntis.cer -CertStoreLocation Cert:\LocalMachine\Root
```

Trusted People is the store Windows uses for a sideload signer. Trusted Root is also required because this certificate is self-signed and has no public certificate authority. It is only a development signer for this package. Do not use it for anything else.

You can do the same thing in the certificate UI: double-click `WebUntis.cer`, choose Install Certificate, choose Local Machine, and place it in both stores.

## Install the package

In the same folder, from a normal PowerShell window:

```powershell
Add-AppxPackage -Path .\WebUntis.msix
```

Then open WebUntis from the Start menu. The window should say that you are not signed in. The WebUntis widget can appear in the Widgets Board only after this package is installed.

## Remove it

```powershell
Get-AppxPackage artiriart.WebUntis | Remove-AppxPackage
Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Subject -eq 'CN=artiriart' -and $_.FriendlyName -eq 'WebUntis development' } | Remove-Item
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -eq 'CN=artiriart' -and $_.FriendlyName -eq 'WebUntis development' } | Remove-Item
```

The removal commands need an administrator PowerShell. They remove only a certificate whose subject and friendly name both match this development certificate.

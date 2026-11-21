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
. (Join-Path $PSScriptRoot 'repack-signable.ps1')
Convert-ToSignableMsix -InputPackage $package.FullName -OutputPackage $unsignedPackage

$testCertificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject 'CN=artiriart' `
    -KeyUsage DigitalSignature `
    -FriendlyName 'WebUntis signability check' `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddDays(1)
$signTools = @(Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' | Sort-Object FullName)
$makeAppxTools = @(Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\makeappx.exe' | Sort-Object FullName)
Write-Host "signtool: $($signTools.FullName -join ' | ')"
Write-Host "makeappx: $($makeAppxTools.FullName -join ' | ')"
if ($makeAppxTools.Count -gt 0) {
    & $makeAppxTools[-1].FullName
}

$layout = Join-Path ([System.IO.Path]::GetTempPath()) 'webuntis-makeappx-layout'
if (Test-Path $layout) { Remove-Item $layout -Recurse -Force }
New-Item -ItemType Directory -Path $layout | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($unsignedPackage, $layout)
foreach ($generated in @('AppxBlockMap.xml', '[Content_Types].xml', 'AppxSignature.p7x')) {
    $generatedPath = Join-Path $layout $generated
    if (Test-Path -LiteralPath $generatedPath) { Remove-Item -LiteralPath $generatedPath -Force }
}
$candidates = @($unsignedPackage)
foreach ($makeAppx in $makeAppxTools) {
    $packed = Join-Path $artifactDir ("packed-" + $makeAppx.Directory.Parent.Name + '.msix')
    & $makeAppx.FullName pack /d $layout /p $packed /o /h SHA256
    Write-Host "makeappx $($makeAppx.FullName) pack exit $LASTEXITCODE"
    if ($LASTEXITCODE -eq 0 -and (Test-Path $packed)) {
        $header = [System.IO.File]::ReadAllBytes($packed)[0..5]
        Write-Host "packed version $([BitConverter]::ToUInt16($header, 4))"
        $candidates += $packed
    }
}

$signed = $false
foreach ($candidate in $candidates) {
    foreach ($signTool in $signTools) {
        foreach ($extension in @('.msix', '.appx')) {
            $testPackage = Join-Path ([System.IO.Path]::GetTempPath()) ("webuntis-sign-test" + $extension)
            Copy-Item $candidate $testPackage -Force
            & $signTool.FullName sign /fd SHA256 /sha1 $testCertificate.Thumbprint $testPackage
            $exitCode = $LASTEXITCODE
            Write-Host "sign $($signTool.Directory.Parent.Name) $extension $(Split-Path $candidate -Leaf) exit $exitCode"
            Remove-Item $testPackage -Force -ErrorAction SilentlyContinue
            if ($exitCode -eq 0) {
                Copy-Item $candidate $unsignedPackage -Force
                $signed = $true
                break
            }
        }
        if ($signed) { break }
    }
    if ($signed) { break }
}
Get-ChildItem $artifactDir -Filter 'packed-*.msix' -ErrorAction SilentlyContinue | Remove-Item -Force
Remove-Item -Path "Cert:\CurrentUser\My\$($testCertificate.Thumbprint)" -ErrorAction SilentlyContinue
if (-not $signed) {
    throw 'No installed signtool could sign the package.'
}

$privateMaterial = Get-ChildItem -Path $artifactDir -Include '*.pfx', '*.pvk', '*.cer' -Recurse -File -ErrorAction SilentlyContinue
if ($privateMaterial) {
    throw 'Certificate material must not be uploaded with the unsigned package.'
}

Copy-Item (Join-Path $repoRoot 'docs\install-windows.md') (Join-Path $artifactDir 'INSTALL.md') -Force
Write-Host "Unsigned package: $unsignedPackage"

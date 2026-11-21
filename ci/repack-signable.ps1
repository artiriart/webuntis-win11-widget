# The Windows App SDK packager writes a Zip64 MSIX. signtool rejects that
# format with "This file format cannot be signed because it is not recognized."
# makeappx pack writes a normal MSIX that signtool can sign.

function Get-WindowsSdkTool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tool = Get-ChildItem -Path 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $tool) {
        throw "$Name was not found. Install the Windows SDK."
    }
    return $tool.FullName
}

function Convert-ToSignableMsix {
    param(
        [Parameter(Mandatory = $true)][string]$InputPackage,
        [Parameter(Mandatory = $true)][string]$OutputPackage
    )

    $layout = Join-Path ([System.IO.Path]::GetTempPath()) ('webuntis-layout-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $layout | Out-Null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($InputPackage, $layout)
        foreach ($generated in @('AppxBlockMap.xml', 'AppxSignature.p7x', '[Content_Types].xml')) {
            $generatedPath = Join-Path $layout $generated
            if (Test-Path -LiteralPath $generatedPath) {
                Remove-Item -LiteralPath $generatedPath -Force
            }
        }

        $makeAppx = Get-WindowsSdkTool 'makeappx.exe'
        & $makeAppx pack /d $layout /p $OutputPackage /o /h SHA256
        if ($LASTEXITCODE -ne 0) {
            throw "makeappx pack failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
    }

    $header = New-Object byte[] 6
    $stream = [System.IO.File]::OpenRead($OutputPackage)
    try {
        [void]$stream.Read($header, 0, $header.Length)
    }
    finally {
        $stream.Dispose()
    }
    $versionNeeded = [BitConverter]::ToUInt16($header, 4)
    if ($versionNeeded -ge 45) {
        throw "Repacked package still requires Zip64 (version $versionNeeded). signtool cannot sign it."
    }
}

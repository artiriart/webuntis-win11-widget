# The Windows App SDK packager writes a Zip64 MSIX. signtool rejects that format.
# This rewrites the same file bytes as a normal ZIP. Integer widths are written
# explicitly because PowerShell can bind BinaryWriter.Write to the wrong overload.

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

function Write-ZipUInt16 {
    param($Writer, [uint16]$Value)
    $Writer.Write([BitConverter]::GetBytes($Value))
}

function Write-ZipUInt32 {
    param($Writer, [uint32]$Value)
    $bytes = [BitConverter]::GetBytes($Value)
    if ($bytes.Length -ne 4) {
        throw "Expected a 4-byte integer, got $($bytes.Length)."
    }
    $Writer.Write($bytes)
}

function Convert-ToSignableMsix {
    param(
        [Parameter(Mandatory = $true)][string]$InputPackage,
        [Parameter(Mandatory = $true)][string]$OutputPackage
    )

    if (-not ('ZipCrc32' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public static class ZipCrc32 {
    static readonly uint[] Table = Init();
    static uint[] Init() {
        var table = new uint[256];
        for (uint i = 0; i < 256; i++) {
            uint crc = i;
            for (int j = 0; j < 8; j++) {
                crc = (crc & 1) != 0 ? 0xEDB88320u ^ (crc >> 1) : crc >> 1;
            }
            table[i] = crc;
        }
        return table;
    }
    public static uint Compute(byte[] data) {
        uint crc = 0xFFFFFFFFu;
        for (int i = 0; i < data.Length; i++) {
            crc = Table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
        }
        return crc ^ 0xFFFFFFFFu;
    }
}
'@
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $layout = Join-Path ([System.IO.Path]::GetTempPath()) ('webuntis-layout-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $layout | Out-Null
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($InputPackage, $layout)
        $files = @(Get-ChildItem -LiteralPath $layout -Recurse -File)
        $priority = @('[Content_Types].xml', 'AppxBlockMap.xml', 'AppxManifest.xml')
        $ordered = @()
        foreach ($name in $priority) {
            $match = $files | Where-Object { $_.Name -eq $name -and $_.DirectoryName -eq $layout }
            if ($match) { $ordered += $match }
        }
        $ordered += @($files | Where-Object { $priority -notcontains $_.Name -or $_.DirectoryName -ne $layout })

        if (Test-Path -LiteralPath $OutputPackage) {
            Remove-Item -LiteralPath $OutputPackage -Force
        }
        $outputStream = [System.IO.File]::Create($OutputPackage)
        $writer = New-Object System.IO.BinaryWriter($outputStream)
        $central = New-Object System.Collections.Generic.List[byte[]]
        try {
            foreach ($file in $ordered) {
                $relative = $file.FullName.Substring($layout.Length).TrimStart('\', '/') -replace '\\', '/'
                $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($relative)
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                $crc = [ZipCrc32]::Compute($bytes)
                $localOffset = [uint32]$outputStream.Position

                $payload = New-Object System.IO.MemoryStream
                $deflate = New-Object System.IO.Compression.DeflateStream($payload, [System.IO.Compression.CompressionLevel]::Optimal, $true)
                $deflate.Write($bytes, 0, $bytes.Length)
                $deflate.Dispose()
                $compressed = $payload.ToArray()
                $method = [uint16]8
                if ($compressed.Length -ge $bytes.Length) {
                    $compressed = $bytes
                    $method = [uint16]0
                }

                Write-ZipUInt32 $writer 0x04034b50
                Write-ZipUInt16 $writer 20
                Write-ZipUInt16 $writer 0
                Write-ZipUInt16 $writer $method
                Write-ZipUInt16 $writer 0
                Write-ZipUInt16 $writer 0
                Write-ZipUInt32 $writer $crc
                Write-ZipUInt32 $writer ([uint32]$compressed.Length)
                Write-ZipUInt32 $writer ([uint32]$bytes.Length)
                Write-ZipUInt16 $writer ([uint16]$nameBytes.Length)
                Write-ZipUInt16 $writer 0
                $writer.Write($nameBytes)
                $writer.Write($compressed)

                $centralStream = New-Object System.IO.MemoryStream
                $centralWriter = New-Object System.IO.BinaryWriter($centralStream)
                Write-ZipUInt32 $centralWriter 0x02014b50
                Write-ZipUInt16 $centralWriter 20
                Write-ZipUInt16 $centralWriter 20
                Write-ZipUInt16 $centralWriter 0
                Write-ZipUInt16 $centralWriter $method
                Write-ZipUInt16 $centralWriter 0
                Write-ZipUInt16 $centralWriter 0
                Write-ZipUInt32 $centralWriter $crc
                Write-ZipUInt32 $centralWriter ([uint32]$compressed.Length)
                Write-ZipUInt32 $centralWriter ([uint32]$bytes.Length)
                Write-ZipUInt16 $centralWriter ([uint16]$nameBytes.Length)
                Write-ZipUInt16 $centralWriter 0
                Write-ZipUInt16 $centralWriter 0
                Write-ZipUInt16 $centralWriter 0
                Write-ZipUInt16 $centralWriter 0
                Write-ZipUInt32 $centralWriter 0
                Write-ZipUInt32 $centralWriter $localOffset
                $centralWriter.Write($nameBytes)
                $centralWriter.Flush()
                $central.Add($centralStream.ToArray())
                $centralWriter.Dispose()
                $payload.Dispose()
            }

            $centralOffset = [uint32]$outputStream.Position
            $centralSize = [uint32]0
            foreach ($entry in $central) {
                $writer.Write($entry)
                $centralSize += [uint32]$entry.Length
            }
            Write-ZipUInt32 $writer 0x06054b50
            Write-ZipUInt16 $writer 0
            Write-ZipUInt16 $writer 0
            Write-ZipUInt16 $writer ([uint16]$central.Count)
            Write-ZipUInt16 $writer ([uint16]$central.Count)
            Write-ZipUInt32 $writer $centralSize
            Write-ZipUInt32 $writer $centralOffset
            Write-ZipUInt16 $writer 0
            $writer.Flush()
        }
        finally {
            $writer.Dispose()
            $outputStream.Dispose()
        }
    }
    finally {
        Remove-Item -LiteralPath $layout -Recurse -Force -ErrorAction SilentlyContinue
    }

    $header = [System.IO.File]::ReadAllBytes($OutputPackage)[0..5]
    $versionNeeded = [BitConverter]::ToUInt16($header, 4)
    if ($header[0] -ne 0x50 -or $header[1] -ne 0x4B -or $versionNeeded -ge 45) {
        throw "Repacked package is not a normal ZIP (version $versionNeeded)."
    }

    $check = [System.IO.Compression.ZipFile]::OpenRead($OutputPackage)
    try {
        if ($check.Entries.Count -lt 3) {
            throw "Repacked package has $($check.Entries.Count) entries."
        }
    }
    finally {
        $check.Dispose()
    }
}

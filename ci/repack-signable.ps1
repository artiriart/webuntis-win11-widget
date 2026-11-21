# The Windows App SDK packager and current makeappx.exe write Zip64 MSIX files.
# signtool rejects those with "This file format cannot be signed because it is not recognized."
# This rewrites the same files as a normal ZIP. File bytes are unchanged, so the block map stays valid.

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
        $files = Get-ChildItem -LiteralPath $layout -Recurse -File
        $priority = @('[Content_Types].xml', 'AppxBlockMap.xml', 'AppxManifest.xml')
        $ordered = @()
        foreach ($name in $priority) {
            $match = $files | Where-Object { $_.Name -eq $name -and $_.DirectoryName -eq $layout }
            if ($match) { $ordered += $match }
        }
        $ordered += $files | Where-Object { $priority -notcontains $_.Name -or $_.DirectoryName -ne $layout }

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

                $writer.Write([uint32]0x04034b50)
                $writer.Write([uint16]20)
                $writer.Write([uint16]0)
                $writer.Write($method)
                $writer.Write([uint16]0)
                $writer.Write([uint16]0)
                $writer.Write([uint32]$crc)
                $writer.Write([uint32]$compressed.Length)
                $writer.Write([uint32]$bytes.Length)
                $writer.Write([uint16]$nameBytes.Length)
                $writer.Write([uint16]0)
                $writer.Write($nameBytes)
                $writer.Write($compressed)

                $centralStream = New-Object System.IO.MemoryStream
                $centralWriter = New-Object System.IO.BinaryWriter($centralStream)
                $centralWriter.Write([uint32]0x02014b50)
                $centralWriter.Write([uint16]20)
                $centralWriter.Write([uint16]20)
                $centralWriter.Write([uint16]0)
                $centralWriter.Write($method)
                $centralWriter.Write([uint16]0)
                $centralWriter.Write([uint16]0)
                $centralWriter.Write([uint32]$crc)
                $centralWriter.Write([uint32]$compressed.Length)
                $centralWriter.Write([uint32]$bytes.Length)
                $centralWriter.Write([uint16]$nameBytes.Length)
                $centralWriter.Write([uint16]0)
                $centralWriter.Write([uint16]0)
                $centralWriter.Write([uint16]0)
                $centralWriter.Write([uint16]0)
                $centralWriter.Write([uint32]0)
                $centralWriter.Write($localOffset)
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
            $writer.Write([uint32]0x06054b50)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]$central.Count)
            $writer.Write([uint16]$central.Count)
            $writer.Write($centralSize)
            $writer.Write($centralOffset)
            $writer.Write([uint16]0)
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

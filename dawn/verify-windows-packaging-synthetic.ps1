[CmdletBinding()]
param(
    [string]$Workspace = (Join-Path ([System.IO.Path]::GetTempPath()) "dawn-jcef-synthetic-windows-packaging")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$fixtureRoot = Join-Path $scriptRoot "test-fixtures\windows-packaging"
$resolvedWorkspaceRoot = [System.IO.Path]::GetFullPath($Workspace)
$resolvedWorkspace = Join-Path $resolvedWorkspaceRoot ("run-" + [guid]::NewGuid().ToString("N"))
$cefRoot = Join-Path $resolvedWorkspace "cef-root"
$nativeDirectory = Join-Path $resolvedWorkspace "native"
$outputDirectory = Join-Path $resolvedWorkspace "artifacts"
$extractDirectory = Join-Path $resolvedWorkspace "extracted"
$expectedCodecRevision = "native-codecs.2"
$expectedArtifactSuffix = "+$expectedCodecRevision"
$expectedReleaseTag = "jcef-d3de827+cef-146.0.10+g8219561+chromium-146.0.7680.179"
$expectedCefVersion = "146.0.12+g316d9cf+chromium-146.0.7680.179"
$requiredFiles = @(
    "chrome_100_percent.pak",
    "chrome_200_percent.pak",
    "chrome_elf.dll",
    "d3dcompiler_47.dll",
    "dxcompiler.dll",
    "dxil.dll",
    "icudtl.dat",
    "jcef.dll",
    "jcef_helper.exe",
    "libEGL.dll",
    "libGLESv2.dll",
    "libcef.dll",
    "resources.pak",
    "v8_context_snapshot.bin",
    "vk_swiftshader.dll",
    "vk_swiftshader_icd.json",
    "vulkan-1.dll"
)

New-Item -ItemType Directory -Path $resolvedWorkspace -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $fixtureRoot "cef-root") -Destination $cefRoot -Recurse

New-Item -ItemType Directory -Path $nativeDirectory | Out-Null
foreach ($file in $requiredFiles) {
    Set-Content -LiteralPath (Join-Path $nativeDirectory $file) -Value "synthetic $file" -Encoding ascii
}
New-Item -ItemType Directory -Path (Join-Path $nativeDirectory "locales") | Out-Null
Set-Content -LiteralPath (Join-Path $nativeDirectory "locales\en-US.pak") -Value "synthetic locale" -Encoding ascii

& (Join-Path $scriptRoot "package-windows-runtime.ps1") `
    -NativeDirectory $nativeDirectory `
    -CefRoot $cefRoot `
    -OutputDirectory $outputDirectory

$jarPath = Join-Path $outputDirectory "jcef-natives-windows-amd64-jcef-d3de827+cef-$expectedCefVersion+$expectedCodecRevision.jar"
$tarPath = Join-Path $outputDirectory "jcef-natives-windows-amd64-jcef-d3de827+cef-$expectedCefVersion+$expectedCodecRevision.tar.gz"
$shaPath = "$jarPath.sha256"

foreach ($path in @($jarPath, $tarPath, $shaPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Synthetic packaging output is missing: $path"
    }
    if (-not ($path.Contains($expectedArtifactSuffix))) {
        throw "Synthetic packaging output does not contain '$expectedArtifactSuffix': $path"
    }
}

New-Item -ItemType Directory -Path $extractDirectory | Out-Null
$embeddedTarName = Split-Path -Leaf $tarPath
$embeddedTarPath = Join-Path $resolvedWorkspace $embeddedTarName
$archive = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
try {
    $payloadEntries = @(
        $archive.Entries | Where-Object {
            -not $_.FullName.EndsWith("/") -and $_.FullName -ne "META-INF/MANIFEST.MF"
        }
    )
    if ($payloadEntries.Count -ne 1) {
        throw "Synthetic packaging jar expected exactly one runtime payload but found $($payloadEntries.Count)."
    }
    $entry = $payloadEntries | Where-Object FullName -eq $embeddedTarName
    if ($null -eq $entry) {
        throw "Synthetic packaging jar is missing embedded runtime archive '$embeddedTarName'."
    }
    $entryStream = $entry.Open()
    $outputStream = [System.IO.File]::Create($embeddedTarPath)
    try {
        $entryStream.CopyTo($outputStream)
    } finally {
        $outputStream.Dispose()
        $entryStream.Dispose()
    }
} finally {
    $archive.Dispose()
}

$standaloneTarSha256 = (Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash
$embeddedTarSha256 = (Get-FileHash -LiteralPath $embeddedTarPath -Algorithm SHA256).Hash
if ($standaloneTarSha256 -ne $embeddedTarSha256) {
    throw "Synthetic packaging jar payload does not match the standalone runtime archive."
}

& tar -xzf $embeddedTarPath -C $extractDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Extracting the jar-embedded synthetic runtime archive failed with exit code $LASTEXITCODE."
}

$buildMetadata = Get-Content -LiteralPath (Join-Path $extractDirectory "build_meta.json") -Raw | ConvertFrom-Json
$expectedMetadata = [ordered]@{
    release_tag = $expectedReleaseTag
    platform = "windows-amd64"
    cef_version = $expectedCefVersion
    dawn_codec_revision = $expectedCodecRevision
}
foreach ($entry in $expectedMetadata.GetEnumerator()) {
    $actual = $buildMetadata.($entry.Key)
    if ($actual -ne $entry.Value) {
        throw "Synthetic packaging metadata '$($entry.Key)' expected '$($entry.Value)' but found '$actual'."
    }
}

$shaLine = (Get-Content -LiteralPath $shaPath -Raw).Trim()
$shaParts = $shaLine -split '\s+', 2
$actualSha256 = (Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($shaParts.Count -ne 2 -or $shaParts[0].ToLowerInvariant() -ne $actualSha256) {
    throw "Synthetic packaging checksum does not match the packaged jar: $shaLine"
}
if ($shaParts[1] -ne (Split-Path -Leaf $jarPath)) {
    throw "Synthetic packaging checksum references the wrong artifact: $shaLine"
}

Write-Host "Synthetic Windows packaging verification passed."
Write-Host "Workspace: $resolvedWorkspace"
Write-Host "Jar: $jarPath"
Write-Host "Tar: $tarPath"
Write-Host "SHA: $shaLine"
Write-Host "build_meta.json: $(Join-Path $extractDirectory 'build_meta.json')"

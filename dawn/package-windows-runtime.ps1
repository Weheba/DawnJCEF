[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NativeDirectory,
    [Parameter(Mandatory = $true)]
    [string]$CefRoot,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$jcefCommit = "d3de827"
$upstreamCefVersion = "146.0.10+g8219561+chromium-146.0.7680.179"
$nativeCefVersion = "146.0.15+g566c566+chromium-146.0.7680.179"
$codecRevision = "native-codecs.3"
$releaseTag = "jcef-d3de827+cef-$upstreamCefVersion"
$platform = "windows-amd64"
$basename = "jcef-natives-$platform-jcef-$jcefCommit+cef-$nativeCefVersion+$codecRevision"

$resolvedNativeDirectory = [System.IO.Path]::GetFullPath($NativeDirectory)
$resolvedCefRoot = [System.IO.Path]::GetFullPath($CefRoot)
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$stagingDirectory = Join-Path $resolvedOutputDirectory "staging-$platform"
$outputPrefix = $resolvedOutputDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar
if (-not $stagingDirectory.StartsWith($outputPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean staging path outside the artifact directory: $stagingDirectory"
}

$cefVersionHeader = Join-Path $resolvedCefRoot "include\cef_version.h"
$cefBuildMarker = Join-Path $resolvedCefRoot "dawn-codec-build.properties"
if (-not (Test-Path -LiteralPath (Join-Path $resolvedCefRoot "cmake\FindCEF.cmake"))) {
    throw "CEF_ROOT is not a CEF binary distribution: $resolvedCefRoot"
}
if (-not (Test-Path -LiteralPath $cefVersionHeader)) {
    throw "CEF_ROOT does not contain include\cef_version.h: $resolvedCefRoot"
}
if (-not (Select-String -LiteralPath $cefVersionHeader -SimpleMatch `
        "#define CEF_VERSION `"$nativeCefVersion`"" -Quiet)) {
    throw "CEF_ROOT has an unexpected CEF version: $resolvedCefRoot"
}
if (-not (Test-Path -LiteralPath $cefBuildMarker)) {
    throw "CEF_ROOT is not a Dawn native-codec distribution: $resolvedCefRoot"
}
$requiredMarkerEntries = @(
    "codec.revision=$codecRevision",
    "cef.source.commit=82195616d8405e6081a0d90924707b82aa9e4141",
    "chromium.version=146.0.7680.179",
    "ffmpeg.branding=Chromium"
)
foreach ($entry in $requiredMarkerEntries) {
    if (-not (Select-String -LiteralPath $cefBuildMarker -SimpleMatch $entry -Quiet)) {
        throw "CEF_ROOT marker is missing '$entry': $resolvedCefRoot"
    }
}

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
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedNativeDirectory $file))) {
        throw "Required JCEF runtime file is missing: $file"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $resolvedNativeDirectory "locales"))) {
    throw "Required JCEF locales directory is missing."
}

New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null
if (Test-Path -LiteralPath $stagingDirectory) {
    Get-ChildItem -LiteralPath $stagingDirectory -Force | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
}

$excludedExtensions = @(".exp", ".ilk", ".lib", ".pdb")
Get-ChildItem -LiteralPath $resolvedNativeDirectory -Force | ForEach-Object {
    if ($_.PSIsContainer) {
        Copy-Item -LiteralPath $_.FullName -Destination $stagingDirectory -Recurse
    } elseif ($excludedExtensions -notcontains $_.Extension.ToLowerInvariant()) {
        Copy-Item -LiteralPath $_.FullName -Destination $stagingDirectory
    }
}

Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "LICENSE.txt") `
    -Destination (Join-Path $stagingDirectory "LICENSE.txt")
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "third_party\jogamp\gluegen.LICENSE.txt") `
    -Destination (Join-Path $stagingDirectory "gluegen.LICENSE.txt")
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "third_party\jogamp\jogl.LICENSE.txt") `
    -Destination (Join-Path $stagingDirectory "jogl.LICENSE.txt")
Copy-Item -LiteralPath (Join-Path $resolvedCefRoot "README.txt") `
    -Destination (Join-Path $stagingDirectory "README.txt")

$metadata = [ordered]@{
    jcef_url = "https://github.com/Weheba/DawnJCEF/commit/d3de8278626c160d4631db3fda2df7b77cc1e5c4"
    release_tag = $releaseTag
    platform = $platform
    cef_source = "https://github.com/Weheba/DawnCEFSource"
    cef_version = $nativeCefVersion
    dawn_codec_revision = $codecRevision
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stagingDirectory "build_meta.json") -Encoding utf8

$tarName = "$basename.tar.gz"
$jarName = "$basename.jar"
$tarPath = Join-Path $resolvedOutputDirectory $tarName
$jarPath = Join-Path $resolvedOutputDirectory $jarName

Push-Location $stagingDirectory
try {
    $entries = Get-ChildItem -Name
    & tar -czf $tarPath @entries
    if ($LASTEXITCODE -ne 0) {
        throw "Creating $tarName failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

& jar --create --file $jarPath -C $resolvedOutputDirectory $tarName
if ($LASTEXITCODE -ne 0) {
    throw "Creating $jarName failed with exit code $LASTEXITCODE."
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $jarPath).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$jarPath.sha256" -Value "$hash  $jarName" -Encoding ascii
Get-Item -LiteralPath $jarPath | Select-Object FullName, Length
Write-Host "SHA256 $hash"

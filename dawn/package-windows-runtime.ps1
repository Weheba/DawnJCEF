[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NativeDirectory,
    [Parameter(Mandatory = $true)]
    [string]$CefRoot,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    # Full SHA of the DawnJCEF commit jcef.dll was built from; build_meta.json's jcef_url names it.
    # Defaults to this checkout's HEAD, which must have no uncommitted changes to tracked files.
    [string]$JcefSourceCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$jcefCommit = "d3de827"
$upstreamCefVersion = "146.0.10+g8219561+chromium-146.0.7680.179"
# Each Dawn codec revision pins one CEF version (see CMakeLists.txt); the CEF root's marker names it.
# native-codecs.5 leaves out OpenH264. native-codecs.4 was never released and is not accepted.
$nativeCefVersions = [ordered]@{
    "native-codecs.3" = "146.0.15+g566c566+chromium-146.0.7680.179"
    "native-codecs.5" = "146.0.28+g2c074f3+chromium-146.0.7680.179"
}
$releaseTag = "jcef-d3de827+cef-$upstreamCefVersion"
$platform = "windows-amd64"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $JcefSourceCommit) {
    $JcefSourceCommit = & git -C $repositoryRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the DawnJCEF commit; pass -JcefSourceCommit."
    }
    $uncommitted = & git -C $repositoryRoot status --porcelain --untracked-files=no
    if ($LASTEXITCODE -ne 0 -or $uncommitted) {
        throw "The DawnJCEF checkout has uncommitted changes, so no commit describes this jcef.dll. Commit them first."
    }
}
$JcefSourceCommit = $JcefSourceCommit.Trim().ToLowerInvariant()
if ($JcefSourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw "JcefSourceCommit must be a full 40-character commit SHA: $JcefSourceCommit"
}
$jcefUrl = "https://github.com/Weheba/DawnJCEF/commit/$JcefSourceCommit"

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
if (-not (Test-Path -LiteralPath $cefBuildMarker)) {
    throw "CEF_ROOT is not a Dawn native-codec distribution: $resolvedCefRoot"
}
$markerLines = @(Get-Content -LiteralPath $cefBuildMarker)
$codecRevision = $nativeCefVersions.Keys | Where-Object { $markerLines -contains "codec.revision=$_" } |
    Select-Object -First 1
if (-not $codecRevision) {
    throw "CEF_ROOT marker names no known Dawn codec revision: $resolvedCefRoot"
}
$nativeCefVersion = $nativeCefVersions[$codecRevision]
$basename = "jcef-natives-$platform-jcef-$jcefCommit+cef-$nativeCefVersion+$codecRevision"
if (-not (Select-String -LiteralPath $cefVersionHeader -SimpleMatch `
        "#define CEF_VERSION `"$nativeCefVersion`"" -Quiet)) {
    throw "CEF_ROOT has an unexpected CEF version: $resolvedCefRoot"
}
$requiredMarkerEntries = @(
    "codec.revision=$codecRevision",
    "cef.source.commit=82195616d8405e6081a0d90924707b82aa9e4141",
    "chromium.version=146.0.7680.179",
    "ffmpeg.branding=Chromium"
)
if ($codecRevision -eq "native-codecs.5") {
    $requiredMarkerEntries += "media.use-openh264=false"
}
foreach ($entry in $requiredMarkerEntries) {
    if ($markerLines -notcontains $entry) {
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

# tools/make_version_header.py stamps jcef.dll's version as <cef>.<commit count>+g<short sha>, so a jcef.dll
# built from another commit than the one jcef_url names is caught here instead of shipping wrong provenance.
$jcefDllVersion = (Get-Item -LiteralPath (Join-Path $resolvedNativeDirectory "jcef.dll")).VersionInfo.ProductVersion
if ($jcefDllVersion -match '\+g([0-9a-f]{7,40})$') {
    if (-not $JcefSourceCommit.StartsWith($Matches[1])) {
        throw "jcef.dll was built from commit $($Matches[1]), not $JcefSourceCommit ($jcefDllVersion)."
    }
} else {
    Write-Warning "jcef.dll carries no '+g<commit>' version; jcef_url is taken on trust: $jcefUrl"
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
    jcef_url = $jcefUrl
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

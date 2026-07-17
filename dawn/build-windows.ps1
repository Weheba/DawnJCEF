[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CefRoot,
    [string]$BuildDirectory = "jcef_build",
    [string]$ArtifactDirectory = "dawn-artifacts",
    [string]$PythonExecutable
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$resolvedCefRoot = [System.IO.Path]::GetFullPath($CefRoot)
$resolvedBuildDirectory = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $BuildDirectory))
$resolvedArtifactDirectory = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $ArtifactDirectory))
$vendoredSix = Join-Path $repositoryRoot "tools\buildtools\external_bin\gsutil\gsutil_4.68\gsutil\third_party\six"
$cmakeArguments = @(
    "-S", $repositoryRoot,
    "-B", $resolvedBuildDirectory,
    "-G", "Visual Studio 17 2022",
    "-A", "x64",
    "-DCEF_ROOT=$resolvedCefRoot",
    "-DDAWN_NATIVE_CODECS=ON"
)

if ($PythonExecutable) {
    $resolvedPythonExecutable = [System.IO.Path]::GetFullPath($PythonExecutable)
    if (-not (Test-Path -LiteralPath $resolvedPythonExecutable -PathType Leaf)) {
        throw "Python executable does not exist: $resolvedPythonExecutable"
    }
    $cmakeArguments += "-DPYTHON_EXECUTABLE=$resolvedPythonExecutable"
}

if (-not (Test-Path -LiteralPath (Join-Path $resolvedCefRoot "cmake\FindCEF.cmake"))) {
    throw "CEF_ROOT is not a CEF binary distribution: $resolvedCefRoot"
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$visualStudio = & $vswhere -latest -products * -version "[17.0,18.0)" `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $visualStudio) {
    throw "Visual Studio 2022 Desktop development with C++ is required."
}

$previousPythonPath = $env:PYTHONPATH
$cmakeExitCode = 1
try {
    $env:PYTHONPATH = if ($previousPythonPath) {
        "$vendoredSix$([System.IO.Path]::PathSeparator)$previousPythonPath"
    } else {
        $vendoredSix
    }
    & cmake @cmakeArguments
    $cmakeExitCode = $LASTEXITCODE
} finally {
    $env:PYTHONPATH = $previousPythonPath
}
if ($cmakeExitCode -ne 0) {
    throw "JCEF CMake configuration failed with exit code $cmakeExitCode."
}

& cmake --build $resolvedBuildDirectory --config Release --parallel
if ($LASTEXITCODE -ne 0) {
    throw "JCEF compilation failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot "package-windows-runtime.ps1") `
    -NativeDirectory (Join-Path $resolvedBuildDirectory "native\Release") `
    -CefRoot $resolvedCefRoot `
    -OutputDirectory $resolvedArtifactDirectory

$ErrorActionPreference = 'Stop'

$buildkitDir = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $buildkitDir 'run_build_tool.cmd'
$testRoot = Join-Path $env:TEMP 'FlClash buildkit resolution test'
$fakeSdk = Join-Path $testRoot 'flutter sdk'
$fakeDart = Join-Path $fakeSdk 'bin\cache\dart-sdk\bin\dart.exe'
$projectRoot = Join-Path $testRoot 'project'
$cmakeTestRoot = Join-Path $env:TEMP 'FlClash cmake resolution test'
$flutterRoot = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
$dartExecutable = Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe'

Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Split-Path -Parent $fakeDart) -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'core') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Value 'name: test_project'
$fakeSource = Join-Path $testRoot 'fake_dart.rs'
Set-Content -LiteralPath $fakeSource -Value 'fn main() {}'
& rustc $fakeSource -o $fakeDart
if ($LASTEXITCODE -ne 0) {
    throw "Could not compile fake Dart executable: rustc exited with $LASTEXITCODE"
}

try {
    Push-Location $projectRoot
    $env:BUILDKIT_DART_EXECUTABLE = $fakeDart
    $env:FLUTTER_ROOT = $null
    & cmd /d /c $launcher windows
    if ($LASTEXITCODE -ne 0) {
        throw "Explicit Dart path test failed with exit code $LASTEXITCODE"
    }

    $env:BUILDKIT_DART_EXECUTABLE = $null
    $env:FLUTTER_ROOT = $fakeSdk
    & cmd /d /c $launcher windows
    if ($LASTEXITCODE -ne 0) {
        throw "FLUTTER_ROOT fallback test failed with exit code $LASTEXITCODE"
    }

    $env:FLUTTER_ROOT = $null
    $output = & cmd /d /c $launcher windows 2>&1
    $exitCode = $LASTEXITCODE
    $diagnostic = $output -join "`n"
    if ($exitCode -eq 0 -or
        $diagnostic -notmatch 'BUILDKIT_DART_EXECUTABLE or FLUTTER_ROOT') {
        throw "Missing SDK test failed: exit=$exitCode output=$diagnostic"
    }

    $cmakeArgs = @(
        "-DBUILDKIT_CMAKE=$($buildkitDir.Replace('\', '/'))/cmake/buildkit.cmake"
        "-DTEST_ROOT=$($cmakeTestRoot.Replace('\', '/'))"
        "-DDART_EXECUTABLE=$($dartExecutable.Replace('\', '/'))"
        '-P'
        (Join-Path $PSScriptRoot 'windows_dart_resolution_test.cmake')
    )
    & cmake @cmakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake Dart resolution test failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
    $env:BUILDKIT_DART_EXECUTABLE = $null
    $env:FLUTTER_ROOT = $null
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $cmakeTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

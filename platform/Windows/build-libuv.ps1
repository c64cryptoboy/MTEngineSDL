param(
    [ValidateSet('Debug','Release','RelWithDebInfo','MinSizeRel')]
    [string]$Config = 'Release',
    [ValidateSet('x64','ARM64')]
    [string]$Platform = 'x64',
    [ValidateSet('Clang','MSVC')]
    [string]$Compiler = 'Clang'
)

$ErrorActionPreference = 'Stop'

function Require-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Missing required tool '$name'. Run from 'Developer PowerShell for VS 2022' and ensure CMake is installed."
    }
}

Require-Command cmake

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$srcDir = Join-Path $repoRoot 'other\lib\libuv'
if (-not (Test-Path (Join-Path $srcDir 'CMakeLists.txt'))) {
    throw "libuv source tree not found at $srcDir"
}

$outDir = Join-Path $repoRoot "platform\Windows\libs\$Platform\$Config"
$buildDir = Join-Path $srcDir "build-windows-$Platform"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$cmakeToolset = if ($Compiler -eq 'Clang') { @('-T', 'ClangCL') } else { @() }

$genMatch = cmake --help | Select-String -Pattern '^\*\s+(Visual Studio \d+ \d+)'
if (-not $genMatch) {
    throw "Could not detect the default Visual Studio CMake generator from 'cmake --help'."
}
$generator = $genMatch.Matches[0].Groups[1].Value

Write-Host "Configuring libuv ($Platform, $Config) in $buildDir"
cmake -S $srcDir -B $buildDir -G $generator -A $Platform @cmakeToolset `
    -DBUILD_SHARED_LIBS=OFF `
    -DLIBUV_BUILD_TESTS=OFF `
    -DLIBUV_BUILD_BENCH=OFF `
    -DBUILD_TESTING=OFF `
    -DCMAKE_MSVC_RUNTIME_LIBRARY="MultiThreaded$<$<CONFIG:Debug>:Debug>"
if ($LASTEXITCODE -ne 0) { throw 'libuv configure failed' }

Write-Host "Building libuv ($Config)"
cmake --build $buildDir --config $Config --target uv_a
if ($LASTEXITCODE -ne 0) { throw 'libuv build failed' }

$built = Get-ChildItem -Path $buildDir -Recurse -File |
    Where-Object { $_.Name -in @('libuv.lib', 'uv.lib', 'uv_a.lib') -and $_.FullName -like "*\$Config\*" } |
    Select-Object -First 1
if (-not $built) { throw 'Expected static libuv library was not found' }

$outLib = Join-Path $outDir 'libuv.lib'
Copy-Item -Force $built.FullName $outLib
Write-Host "Done. Output: $outLib"

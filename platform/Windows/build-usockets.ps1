param(
    [ValidateSet('Debug','Release')]
    [string]$Config = 'Release',
    [ValidateSet('x64','ARM64')]
    [string]$Platform = 'x64',
    [ValidateSet('Clang','MSVC')]
    [string]$Compiler = 'Clang'
)

$ErrorActionPreference = 'Stop'

$compilerCommand = if ($Compiler -eq 'Clang') { 'clang-cl' } else { 'cl' }
foreach ($tool in @($compilerCommand, 'lib')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Missing required tool '$tool'. Run from 'Developer PowerShell for Visual Studio'."
    }
}

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$srcRoot = Join-Path $repoRoot 'other\lib\uSockets\src'
$uvInclude = Join-Path $repoRoot 'other\lib\libuv\include'
if (-not (Test-Path $srcRoot)) { throw "uSockets source tree not found at $srcRoot" }
if (-not (Test-Path $uvInclude)) { throw "libuv headers not found at $uvInclude" }

$outDir = Join-Path $repoRoot "platform\Windows\libs\$Platform\$Config"
$objDir = Join-Path $repoRoot "other\lib\uSockets.build-windows-$Platform-$Config"
$outLib = Join-Path $outDir 'uSockets.lib'
$stamp = Join-Path $outDir 'uSockets.stamp'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$scriptSha = (Get-FileHash -Algorithm SHA256 -Path $PSCommandPath).Hash.ToLowerInvariant()
$stampValue = "$scriptSha`:$Config`:$Platform`:$Compiler"
if ((Test-Path $outLib) -and (Test-Path $stamp) -and
    ((Get-Content $stamp -Raw).Trim() -eq $stampValue)) {
    Write-Host "uSockets is up to date: $outLib"
    exit 0
}

$sources = @(
    'bsd.c',
    'context.c',
    'crypto\openssl.c',
    'crypto\sni_tree.cpp',
    'eventing\asio.cpp',
    'eventing\epoll_kqueue.c',
    'eventing\gcd.c',
    'eventing\libuv.c',
    'io_uring\io_context.c',
    'io_uring\io_loop.c',
    'io_uring\io_socket.c',
    'loop.c',
    'quic.c',
    'socket.c',
    'udp.c'
)

if (Test-Path $objDir) { Remove-Item -Recurse -Force $objDir }
New-Item -ItemType Directory -Force -Path $objDir | Out-Null

$crtFlag = if ($Config -eq 'Debug') { '/MTd' } else { '/MT' }
$buildFlags = if ($Config -eq 'Debug') { @('/Od', '/Z7', '/D_DEBUG') } else { @('/O2', '/DNDEBUG') }
$commonFlags = @('/nologo', '/c', $crtFlag, '/D_LIB', '/DLIBUS_NO_SSL', '/D_CRT_SECURE_NO_WARNINGS', "/I$srcRoot", "/I$uvInclude")

Write-Host "Compiling uSockets ($Platform, $Config)"
$objects = @()
foreach ($relativePath in $sources) {
    $source = Join-Path $srcRoot $relativePath
    $objectName = ($relativePath -replace '[\\/]', '_') -replace '\.(c|cpp)$', '.obj'
    $object = Join-Path $objDir $objectName
    & $compilerCommand @commonFlags @buildFlags $source "/Fo$object"
    if ($LASTEXITCODE -ne 0) { throw "uSockets compile failed: $relativePath" }
    $objects += $object
}

if (Test-Path $outLib) { Remove-Item -Force $outLib }
& lib /nologo "/OUT:$outLib" @objects
if ($LASTEXITCODE -ne 0) { throw 'uSockets archive creation failed' }

Set-Content -NoNewline -Path $stamp -Value $stampValue
Write-Host "Done. Output: $outLib"

param(
    [ValidateSet('Install','Uninstall','Check')][string]$Action = 'Check',
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Antimatter Dimensions',
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'AntimatterDimensionsWhiteScreenRecovery')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$utf8 = New-Object System.Text.UTF8Encoding($false)
$archive = Join-Path $GameRoot 'resources\app.asar'
$stateFile = Join-Path $StateRoot 'state.json'
$backup = Join-Path $StateRoot 'original-app.asar'
$payloadFile = Join-Path $PSScriptRoot 'payload\ad-white-screen-recovery.js'

function Get-Hash([string]$file) { return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
function Read-Archive([string]$file) {
    $stream = [IO.File]::OpenRead($file)
    try {
        $prefix = New-Object byte[] 16
        if ($stream.Read($prefix,0,16) -ne 16) { throw 'Invalid ASAR prefix.' }
        $headerSize = [BitConverter]::ToUInt32($prefix,4)
        $jsonSize = [BitConverter]::ToUInt32($prefix,12)
        if ($jsonSize -lt 2 -or $jsonSize -gt 16777216 -or $headerSize -lt $jsonSize + 8) { throw 'Invalid ASAR header.' }
        $bytes = New-Object byte[] $jsonSize
        if ($stream.Read($bytes,0,$jsonSize) -ne $jsonSize) { throw 'Incomplete ASAR header.' }
        return [pscustomobject]@{ Header=($utf8.GetString($bytes) | ConvertFrom-Json); DataStart=([long]8+$headerSize); Length=$stream.Length }
    } finally { $stream.Dispose() }
}
function Get-Entry($header,[string]$entryPath) {
    $entry = $header
    foreach ($part in $entryPath.Split('/')) {
        $property = $entry.files.PSObject.Properties[$part]
        if ($null -eq $property) { throw "Missing archive entry: $entryPath" }
        $entry = $property.Value
    }
    return $entry
}
function Read-Entry([string]$file,$info,[string]$entryPath) {
    $entry = Get-Entry $info.Header $entryPath
    if ($entry.size -gt 10485760) { throw "Entry unexpectedly large: $entryPath" }
    $stream = [IO.File]::OpenRead($file)
    try {
        [void]$stream.Seek(($info.DataStart+[long]$entry.offset),[IO.SeekOrigin]::Begin)
        $bytes = New-Object byte[] ([int]$entry.size)
        if ($stream.Read($bytes,0,$bytes.Length) -ne $bytes.Length) { throw "Incomplete entry: $entryPath" }
        return ,$bytes
    } finally { $stream.Dispose() }
}
function Update-Integrity($entry,[byte[]]$bytes) {
    if ($null -eq $entry.PSObject.Properties['integrity']) { return }
    $integrity = $entry.integrity
    if ($integrity.algorithm -ne 'SHA256') { throw 'Unsupported archive integrity algorithm.' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $integrity.hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
        $blockSize = [int]$integrity.blockSize
        if ($blockSize -lt 1) { throw 'Invalid integrity block size.' }
        $blocks = @()
        for ($i=0; $i -lt $bytes.Length; $i+=$blockSize) {
            $count = [Math]::Min($blockSize,$bytes.Length-$i)
            $blocks += ([BitConverter]::ToString($sha.ComputeHash($bytes,$i,$count))).Replace('-','').ToLowerInvariant()
        }
        $integrity.blocks = @($blocks)
    } finally { $sha.Dispose() }
}
function Assert-GameClosed {
    $running = @(Get-Process -Name 'Antimatter Dimensions' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and [IO.Path]::GetDirectoryName($_.Path) -eq [IO.Path]::GetFullPath($GameRoot) } catch { $false }
    })
    if ($running.Count -gt 0) { throw 'Please close Antimatter Dimensions before installing or uninstalling.' }
}
function Save-State($value) {
    [IO.Directory]::CreateDirectory($StateRoot) | Out-Null
    [IO.File]::WriteAllText($stateFile,($value | ConvertTo-Json -Depth 8),$utf8)
}
function Replace-Archive([string]$source,[string]$expectedCurrentHash) {
    if ((Get-Hash $archive) -ne $expectedCurrentHash) { throw 'Game files changed during this operation. Nothing was replaced.' }
    [IO.File]::Replace($source,$archive,[System.Management.Automation.Language.NullString]::Value)
}

if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Game archive not found: $archive" }
$currentHash = Get-Hash $archive
$state = $null
if (Test-Path -LiteralPath $stateFile) { $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json }

if ($Action -eq 'Check') {
    $info = Read-Archive $archive
    $main = $utf8.GetString((Read-Entry $archive $info 'main.js'))
    [pscustomobject]@{
        GameRoot=$GameRoot
        RecoveryMarkerPresent=$main.Contains('AD-WHITE-SCREEN-RECOVERY:1.0.0')
        RecordedState=$(if ($state) { $state.status } else { 'not-installed' })
        MatchesInstalledArchive=($state -and $state.installedHash -eq $currentHash)
        ArchiveSHA256=$currentHash
    } | Format-List
    exit 0
}

Assert-GameClosed
if ($Action -eq 'Uninstall') {
    if (-not $state -or $state.status -ne 'installed') { throw 'No installed recovery add-on was recorded.' }
    if ($state.installedHash -ne $currentHash) { throw 'Another update changed the archive. Refusing to overwrite it.' }
    if (-not (Test-Path -LiteralPath $backup) -or (Get-Hash $backup) -ne $state.originalHash) { throw 'Original backup is missing or failed verification.' }
    $temporary = Join-Path (Split-Path -Parent $archive) ('app.asar.recovery-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        Copy-Item -LiteralPath $backup -Destination $temporary
        Replace-Archive $temporary $currentHash
        $state.status = 'uninstalled'
        Save-State $state
        Write-Output 'Recovery add-on removed. The exact pre-install archive was restored.'
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    exit 0
}

if ($state -and $state.status -eq 'installed') {
    if ($state.installedHash -eq $currentHash) { Write-Output 'Recovery add-on is already installed.'; exit 0 }
    throw 'Recorded installation no longer matches this archive. Refusing to overwrite it.'
}
if (-not (Test-Path -LiteralPath $payloadFile)) { throw 'Recovery payload is missing. Extract the entire package first.' }
$info = Read-Archive $archive
$version = $utf8.GetString((Read-Entry $archive $info 'AppFiles/version.txt')) | ConvertFrom-Json
if ([string]$version.version -ne '11.5') { throw 'This add-on has only been prepared for game version 11.5.' }
$main = $utf8.GetString((Read-Entry $archive $info 'main.js'))
$anchor = "  mainWindow.loadFile('AppFiles/index.html')"
if ($main.Contains('AD-WHITE-SCREEN-RECOVERY') -or ([regex]::Matches($main,[regex]::Escape($anchor))).Count -ne 1) {
    throw 'Unexpected main.js structure. Nothing was changed.'
}
$injection = "  // AD-WHITE-SCREEN-RECOVERY:1.0.0`r`n  require('./ad-white-screen-recovery').attach(mainWindow)`r`n`r`n"
$mainBytes = $utf8.GetBytes($main.Replace($anchor,$injection+$anchor))
$payloadBytes = [IO.File]::ReadAllBytes($payloadFile)
$dataLength = $info.Length-$info.DataStart
$mainEntry = Get-Entry $info.Header 'main.js'
$mainEntry.offset = [string]$dataLength
$mainEntry.size = $mainBytes.Length
Update-Integrity $mainEntry $mainBytes
if ($null -ne $info.Header.files.PSObject.Properties['ad-white-screen-recovery.js']) { throw 'Unexpected recovery file already exists.' }
$info.Header.files | Add-Member -MemberType NoteProperty -Name 'ad-white-screen-recovery.js' -Value ([pscustomobject]@{
    size=$payloadBytes.Length; offset=[string]($dataLength+$mainBytes.Length)
})
$jsonBytes = $utf8.GetBytes(($info.Header | ConvertTo-Json -Depth 100 -Compress))
$padding = (4-($jsonBytes.Length % 4)) % 4
$newHeaderSize = 8+$jsonBytes.Length+$padding
$prefix = New-Object byte[] 16
[Array]::Copy([BitConverter]::GetBytes([uint32]4),0,$prefix,0,4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$newHeaderSize),0,$prefix,4,4)
[Array]::Copy([BitConverter]::GetBytes([uint32]($newHeaderSize-4)),0,$prefix,8,4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$jsonBytes.Length),0,$prefix,12,4)

[IO.Directory]::CreateDirectory($StateRoot) | Out-Null
if (Test-Path -LiteralPath $backup) {
    if ((Get-Hash $backup) -ne $currentHash) { throw 'An existing backup belongs to another archive. Use a new state folder.' }
} else { Copy-Item -LiteralPath $archive -Destination $backup }
if ((Get-Hash $backup) -ne $currentHash) { throw 'Backup verification failed.' }
$temporary = Join-Path (Split-Path -Parent $archive) ('app.asar.recovery-'+[guid]::NewGuid().ToString('N')+'.tmp')
try {
    $archiveInput = [IO.File]::OpenRead($archive)
    $archiveOutput = [IO.File]::Create($temporary)
    try {
        $archiveOutput.Write($prefix,0,$prefix.Length)
        $archiveOutput.Write($jsonBytes,0,$jsonBytes.Length)
        if ($padding) { $archiveOutput.Write((New-Object byte[] $padding),0,$padding) }
        [void]$archiveInput.Seek($info.DataStart,[IO.SeekOrigin]::Begin)
        $archiveInput.CopyTo($archiveOutput)
        $archiveOutput.Write($mainBytes,0,$mainBytes.Length)
        $archiveOutput.Write($payloadBytes,0,$payloadBytes.Length)
    } finally { $archiveOutput.Dispose(); $archiveInput.Dispose() }
    $newInfo = Read-Archive $temporary
    if ($utf8.GetString((Read-Entry $temporary $newInfo 'main.js')) -ne $utf8.GetString($mainBytes)) { throw 'Patched archive validation failed.' }
    $newHash = Get-Hash $temporary
    $newState = [pscustomobject]@{
        status='prepared'; version='1.0.0'; originalHash=$currentHash; installedHash=$newHash;
        gameRoot=[IO.Path]::GetFullPath($GameRoot); installedAt=(Get-Date).ToUniversalTime().ToString('o')
    }
    Save-State $newState
    Replace-Archive $temporary $currentHash
    $newState.status = 'installed'
    Save-State $newState
    Write-Output 'Installed. Start the game, then press F5 (or Ctrl+Alt+R) while its window is focused to reload the page.'
    Write-Output 'If normal reload stalls, the add-on will recreate only the renderer after 8 seconds.'
    Write-Output "Backup: $backup"
} finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }

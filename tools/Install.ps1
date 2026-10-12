param(
    [Parameter(Mandatory=$true)][string]$GameDirectory,
    [Parameter(Mandatory=$true)][string]$SaveDirectory,
    [Parameter(Mandatory=$true)][string]$BackupDirectory
)
$ErrorActionPreference='Stop'
function Assert-GameClosed {
    if(@(Get-Process | Where-Object {$_.ProcessName -match '^(DD2|DDDA)$'}).Count){throw 'Quit the game normally before installation.'}
}
Assert-GameClosed
$game=(Resolve-Path -LiteralPath $GameDirectory).Path
$saves=(Resolve-Path -LiteralPath $SaveDirectory).Path
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$backupBase=[IO.Path]::GetFullPath($BackupDirectory)
if(!(Test-Path -LiteralPath (Join-Path $game 'DD2.exe'))){throw 'Game directory does not contain DD2.exe.'}
if(!(Test-Path -LiteralPath (Join-Path $game 'dinput8.dll'))){throw 'Install REFramework separately first.'}
if((Split-Path $saves -Leaf) -ne '2054970'){throw 'SaveDirectory must be the DD2 Steam app folder named 2054970.'}
foreach($privateParent in @($repo,$game,$saves)){
    if($backupBase.Equals($privateParent,[StringComparison]::OrdinalIgnoreCase) -or $backupBase.StartsWith($privateParent.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
        throw 'Choose a backup directory outside the repository, game directory and save directory.'
    }
}
$source=Join-Path $repo 'src\AtlasSnapshot-DD2.lua'
$expected=(Get-FileHash -LiteralPath $source).Hash
$target=Join-Path $game 'reframework\autorun\AtlasSnapshot-DD2-probe.lua'
$backup=Join-Path $backupBase ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'Z')
New-Item -ItemType Directory -Path $backup | Out-Null
$records=@()
foreach($file in Get-ChildItem -LiteralPath $saves -File -Recurse){
    $relative=$file.FullName.Substring($saves.Length+1)
    $dest=Join-Path (Join-Path $backup 'saves') $relative
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    $hash=(Get-FileHash -LiteralPath $file.FullName).Hash
    Copy-Item -LiteralPath $file.FullName -Destination $dest
    if((Get-FileHash -LiteralPath $dest).Hash -ne $hash){throw 'Save backup hash mismatch.'}
    $records+=[pscustomobject]@{relativePath=$relative;sha256=$hash}
}
if(!$records.Count){throw 'No save files found; nothing installed.'}
$records | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'save-hashes.json')
$previousHash=$null
if(Test-Path -LiteralPath $target){
    $previousHash=(Get-FileHash -LiteralPath $target).Hash
    Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'previous-reader.lua')
    if((Get-FileHash -LiteralPath (Join-Path $backup 'previous-reader.lua')).Hash -ne $previousHash){throw 'Reader backup hash mismatch.'}
}
Assert-GameClosed
New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $target -Force
if((Get-FileHash -LiteralPath $target).Hash -ne $expected){throw 'Installed source hash mismatch.'}
if(@(Get-ChildItem -LiteralPath $saves -File -Recurse).Count -ne $records.Count){throw 'Save file count changed during installation.'}
foreach($record in $records){if((Get-FileHash -LiteralPath (Join-Path $saves $record.relativePath)).Hash -ne $record.sha256){throw 'Save changed during installation.'}}
[ordered]@{target=$target;installedSHA256=$expected;previousSHA256=$previousHash;saveFilesUnchanged=$records.Count;verifiedAtUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'install-record.json')
Write-Output "Installed reader; source hash and unchanged saves verified. Private backup: $backup"

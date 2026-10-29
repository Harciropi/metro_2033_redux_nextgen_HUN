param([string]$SdkPath)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'prepare-package.ps1') -LibraryOnly
$scratchParent=[IO.Path]::GetTempPath()
$testRoot=Join-Path $scratchParent ('metro2033-components-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot)|Out-Null
try{
$package=New-HuPackage (Join-Path $testRoot 'package') $projectRoot
. $package.Backend -LibraryOnly
$payload=$package.Payload;$pkg=Read-HuPackage $payload
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Ok,[string]$Name){if(-not $Ok){throw ('FAILED: '+$Name)};$checks.Add($Name)}
function Rejected([scriptblock]$Action,[string]$Expected,[string]$Name){$actual='NO_ERROR';try{& $Action|Out-Null}catch{$actual=$_.Exception.Message};Check ($actual -eq $Expected) ($Name+' ['+$actual+']')}
function Assert-Fixture([string]$Folder){if(-not [IO.Path]::GetFullPath($Folder).StartsWith($testRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'OUTSIDE_FIXTURE'}}
$original=[IO.File]::ReadAllBytes((Join-Path $payload 'original-content.vfx'));$originalHash=Get-HuBytesHash $original
$SdkPath=Get-HuTestSdk $SdkPath
$sdk=[IO.File]::ReadAllBytes($SdkPath);$sdkHash=Get-HuBytesHash $sdk
Check ([Metro2033Hu.BannerFilter]::Inspect($sdk) -eq 'ORIGINAL') '2033 SDK matches checked exports and native code structure'
$filtered=[Metro2033Hu.BannerFilter]::Apply($sdk);$sdkFilteredHash=Get-HuBytesHash $filtered
$diff=@(for($n=0;$n -lt $sdk.Length;$n++){if($sdk[$n] -ne $filtered[$n]){$n}})
Check ($diff.Count -eq 2 -and $filtered[$diff[0]] -eq 0x90 -and $filtered[$diff[1]] -eq 0x90 -and $sdk[$diff[0]] -eq 0x74 -and $sdk[$diff[1]] -eq 0x10) 'only the SDK native initialization-success branch is disabled'
Check ([Metro2033Hu.BannerFilter]::Inspect($filtered) -eq 'FILTERED') 'filtered SDK is recognized'
[IO.File]::WriteAllBytes((Join-Path $testRoot 'sdk-original.dll'),$sdk)
[IO.File]::WriteAllBytes((Join-Path $testRoot 'sdk-disabled.dll'),$filtered)
function New-Fixture([string]$Name){
 $f=Join-Path $testRoot ($Name+'\steamapps\common\MetroFixture');Assert-Fixture $f
 [IO.Directory]::CreateDirectory($f)|Out-Null
 foreach($name in @('metro.exe','steam_api64.dll','amd_fidelityfx_dx12.dll','uTelemetry.dll')){[IO.File]::WriteAllText((Join-Path $f $name),'FIXTURE ONLY - NOT EXECUTABLE')}
 [IO.File]::WriteAllBytes((Join-Path $f 'content.vfx'),$original);[IO.File]::WriteAllBytes((Join-Path $f 'pros.sdk.x64.dll'),$sdk)
 [IO.File]::WriteAllText((Join-Path (Split-Path (Split-Path $f)) 'appmanifest_286690.acf'),'"AppState" { "appid" "286690" "StateFlags" "4" "installdir" "MetroFixture" "buildid" "fixture-unpinned" }')
 [IO.File]::WriteAllText((Join-Path $f 'user-note.txt'),'preserve user data')
 return $f
}
function Apply([string]$Folder,[string]$Selection,$Package=$pkg){Assert-Fixture $Folder;Invoke-HuOperation $Folder $Package $payload 'Apply' $Selection}
function Remove-Fixture([string]$Folder){Assert-Fixture $Folder;Invoke-HuOperation $Folder $pkg $payload 'Remove' 'None'}
$template=[Metro2033Hu.ResourceIndex]::new([IO.File]::ReadAllBytes((Join-Path $payload 'content.vfx')))
$language=$template.Extract($payload,'content/localization/stable_us.lng')
function Check-Selection([string]$Folder,[string]$Selection){
 $s=Read-HuState $Folder
 Check ((Format-HuComponents @(Get-HuInstalledComponents $s)) -eq $Selection) ('recorded components '+$Selection)
 if($Selection -like '*Translation*'){
  $i=[Metro2033Hu.ResourceIndex]::new([IO.File]::ReadAllBytes((Join-Path $Folder 'content.vfx')))
  Check ((Get-HuBytesHash ($i.Extract($Folder,'content/localization/stable_us.lng'))) -eq (Get-HuBytesHash $language)) 'translation bytes exactly match unchanged 1.5.3 language'
  $source=[Metro2033Hu.ResourceIndex]::new($original)
  $unchanged=$true;foreach($key in $source.Files.Keys){if($key -eq 'content/localization/stable_us.lng'){continue};$a=$source.Files[$key];$b=$i.Files[$key];if($a.Archive -ne $b.Archive -or $a.Offset -ne $b.Offset -or $a.Unpacked -ne $b.Unpacked -or $a.Packed -ne $b.Packed){$unchanged=$false;break}}
  Check $unchanged 'fonts, config, UI and every unrelated resource retain original references'
 }else{
  Check ((Get-HuHash (Join-Path $Folder 'content.vfx')) -eq $originalHash) 'ads-only leaves original resource index byte-identical'
  Check (-not (Test-Path -LiteralPath (Join-Path $Folder $HuArchive))) 'ads-only has no translation archive'
 }
 $expected=if($Selection -like '*HideAds*'){$sdkFilteredHash}else{$sdkHash}
 Check ((Get-HuHash (Join-Path $Folder 'pros.sdk.x64.dll')) -eq $expected) 'SDK matches selected component'
 foreach($file in @('metro.exe','steam_api64.dll','uTelemetry.dll')){Check ([IO.File]::ReadAllText((Join-Path $Folder $file)) -eq 'FIXTURE ONLY - NOT EXECUTABLE') ('unrelated binary untouched '+$file)}
}
foreach($from in @('Translation','HideAds','Translation,HideAds')){foreach($to in @('Translation','HideAds','Translation,HideAds')){
 $f=New-Fixture ('switch-'+$from.Replace(',','-')+'-'+$to.Replace(',','-'))
 Check ((Get-HuState $f $pkg) -eq 'READY_INSTALL') 'fresh install detection'
 $mtime=(Get-Item -LiteralPath (Join-Path $f 'content.vfx')).LastWriteTimeUtc.Ticks
 Check ((Apply $f $from) -eq 'INSTALLED') ('fresh installation '+$from);Check-Selection $f $from
 if($from -eq 'HideAds'){Check ((Get-Item -LiteralPath (Join-Path $f 'content.vfx')).LastWriteTimeUtc.Ticks -eq $mtime) 'ads-only does not rewrite the index'}
 $first=Read-HuState $f;$expected=if($from -eq $to){'UNCHANGED'}else{'INSTALLED'}
 Check ((Apply $f $to) -eq $expected) ('component switch '+$from+' -> '+$to);Check-Selection $f $to
 $last=Read-HuState $f;Check ($first.OriginalName -eq $last.OriginalName -and $first.OriginalHash -eq $last.OriginalHash) 'original backup preserved during switch'
 Check ((Remove-Fixture $f) -eq 'REMOVED') 'full removal succeeds'
 Check ((Get-HuHash (Join-Path $f 'content.vfx')) -eq $originalHash -and (Get-HuHash (Join-Path $f 'pros.sdk.x64.dll')) -eq $sdkHash) 'full removal restores both original files'
 Check (-not (Test-Path -LiteralPath (Join-Path $f $HuBackup))) 'full removal deletes all own backups and empty directory'
 Check ([IO.File]::ReadAllText((Join-Path $f 'user-note.txt')) -eq 'preserve user data') 'user file preserved'
}}
# Real legacy 1.5.3 source and state are simulated entirely in fixtures.
foreach($selection in @('Translation','HideAds','Translation,HideAds','None')){
 $f=New-Fixture ('legacy-'+$selection.Replace(',','-'));$legacy=Join-Path $f $HuBackup;[IO.Directory]::CreateDirectory($legacy)|Out-Null
 Copy-Item -LiteralPath (Join-Path $payload 'content.vfx'),(Join-Path $payload $HuArchive) -Destination $f
 $name='eredeti-'+[guid]::NewGuid().ToString('N')+'.vfx';[IO.File]::WriteAllBytes((Join-Path $legacy $name),$original);[IO.File]::WriteAllBytes((Join-Path $legacy 'content.vfx'),$original)
 [IO.File]::WriteAllText((Join-Path $legacy 'allapot.ini'),("[Magyaritas]`r`nVersion=1.5.3`r`nOriginalFile=$name`r`nOriginalHash=$originalHash`r`n"),[Text.Encoding]::Unicode)
 Check ((Get-HuState $f $pkg 'None') -eq 'READY_UPGRADE') 'old 1.5.3 installer detected'
 Check ($script:HuDetectedComponents -eq 'Translation') 'legacy defaults to translation only'
 if($selection -ne 'None'){
  Check ((Apply $f $selection) -eq 'INSTALLED') ('legacy upgrade '+$selection);Check-Selection $f $selection
  Check ((Read-HuState $f).OriginalName -eq $name) 'legacy original backup retained'
 }
 Check ((Remove-Fixture $f) -eq 'REMOVED') 'legacy or upgraded installation removes'
 Check (-not (Test-Path -LiteralPath $legacy)) 'legacy INI, duplicate original and old backup cleaned only after restoration'
}
foreach($selection in @('Translation','HideAds','Translation,HideAds')){
 $f=New-Fixture ('upgrade-'+$selection.Replace(',','-'));$old=$pkg|ConvertTo-Json -Depth 8|ConvertFrom-Json;$old.Version='1.5.9'
 Apply $f $selection $old|Out-Null
 Check ((Invoke-HuOperation $f $pkg $payload 'Install' '') -eq 'INSTALLED') 'upgrade preserves previous choice without explicit selection';Check-Selection $f $selection
}
$f=New-Fixture 'same-version-rebuild';Apply $f 'Translation'|Out-Null;$s=Read-HuState $f;$s.PackageHash='F'*64;Write-HuJson (Join-Path (Join-Path $f $HuBackup) 'state.json') $s
Check ((Get-HuState $f $pkg) -eq 'READY_UPGRADE') 'unpublished rebuild with unchanged version can be upgraded'
Check ((Apply $f 'Translation') -eq 'INSTALLED') 'same-version rebuild accepted after owned file verification'
$f=New-Fixture 'foreign-note';Apply $f 'Translation,HideAds'|Out-Null;$backup=Join-Path $f $HuBackup
[IO.File]::WriteAllText((Join-Path $backup 'personal.txt'),'keep');Remove-Fixture $f|Out-Null
Check (@(Get-ChildItem -LiteralPath $backup).Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $backup 'personal.txt'))) 'foreign file in backup directory preserved'
$f=New-Fixture 'partial-backups';Apply $f 'Translation,HideAds'|Out-Null;Apply $f 'Translation'|Out-Null
Check (@(Get-ChildItem -LiteralPath (Join-Path $f $HuBackup) -Filter 'sdk-original-*').Count -eq 1) 'partial restore keeps SDK backup for later changes'
$f=New-Fixture 'unknown-sdk';[IO.File]::WriteAllText((Join-Path $f 'pros.sdk.x64.dll'),'unknown')
Check ((Apply $f 'Translation') -eq 'INSTALLED') 'translation independent of unsupported SDK';Rejected {Apply $f 'Translation,HideAds'} 'BANNER_UNSUPPORTED' 'unknown SDK refused'
$f=New-Fixture 'foreign-filter';[IO.File]::WriteAllBytes((Join-Path $f 'pros.sdk.x64.dll'),$filtered)
Rejected {Apply $f 'HideAds'} 'FILE_CONFLICT' 'unowned already-modified SDK refused'
$f=New-Fixture 'foreign-converter';$foreign=[byte[]]$sdk.Clone()
foreach($offset in [Metro2033Hu.BannerFilter]::Offsets($foreign)){$foreign[$offset]=0x90}
[IO.File]::WriteAllBytes((Join-Path $f 'pros.sdk.x64.dll'),$foreign)
Rejected {Apply $f 'HideAds'} 'BANNER_UNSUPPORTED' 'foreign converter-only patch is not adopted as a 2033 original'
$f=New-Fixture 'foreign-branch';$foreign=[byte[]]$sdk.Clone();$foreign[$diff[0]]=0xEB
[IO.File]::WriteAllBytes((Join-Path $f 'pros.sdk.x64.dll'),$foreign)
Rejected {Apply $f 'HideAds'} 'BANNER_UNSUPPORTED' 'unknown SDK initialization branch refused'
$f=New-Fixture 'corrupt-backup';Apply $f 'Translation,HideAds'|Out-Null;$s=Read-HuState $f
[IO.File]::AppendAllText((Join-Path (Join-Path $f $HuBackup) $s.SdkOriginalName),'corrupt')
Rejected {Remove-Fixture $f} 'BACKUP_CONFLICT' 'corrupt SDK backup prevents restoration'
Check ((Get-HuHash (Join-Path $f 'pros.sdk.x64.dll')) -eq $sdkFilteredHash) 'failed restoration leaves live fixture untouched'
Check (Test-Path -LiteralPath (Join-Path $f $HuBackup)) 'failed restoration retains backups'
$f=New-Fixture 'foreign-owned-sdk';Apply $f 'HideAds'|Out-Null;[IO.File]::AppendAllText((Join-Path $f 'pros.sdk.x64.dll'),'foreign')
Rejected {Apply $f 'Translation'} 'FILE_CONFLICT' 'unknown modification to installed SDK refused'
$f=New-Fixture 'pending';Apply $f 'Translation'|Out-Null;[IO.File]::WriteAllText((Join-Path (Join-Path $f $HuBackup) 'pending.json'),'interrupted')
Rejected {Remove-Fixture $f} 'RECOVERY_NEEDED' 'interrupted transaction retains backups and blocks cleanup'
foreach($failed in @('pros.sdk.x64.dll','state.json')){
 $f=New-Fixture ('rollback-'+$failed);$script:failName=$failed;$script:failOnce=$true;$saved=${function:Write-HuAtomic}
 function Write-HuAtomic([string]$Path,[byte[]]$Bytes){if($script:failOnce -and [IO.Path]::GetFileName($Path) -eq $script:failName){$script:failOnce=$false;throw 'COPY_FAILED'};& $saved $Path $Bytes}
 try{Rejected {Apply $f 'Translation,HideAds'} 'COPY_FAILED' 'transaction write failure reported'}finally{Set-Item function:Write-HuAtomic $saved}
 Check ((Get-HuHash (Join-Path $f 'content.vfx')) -eq $originalHash -and (Get-HuHash (Join-Path $f 'pros.sdk.x64.dll')) -eq $sdkHash) 'transaction failure rolls back index and SDK'
 Check (-not (Test-Path -LiteralPath (Join-Path $f $HuArchive))) 'transaction failure removes only incomplete own archive'
}
$f=New-Fixture 'invalid';Rejected {Apply $f 'None'} 'NO_COMPONENTS' 'empty install selection refused';Rejected {Apply $f 'Translation,Translation'} 'BAD_COMPONENTS' 'duplicate selection refused'
# Steam detection uses synthetic VDF/ACF on the filesystem, never registry writes.
$found=New-Fixture 'steam-library';$steam=Join-Path $testRoot 'steam-client';[IO.Directory]::CreateDirectory((Join-Path $steam 'steamapps'))|Out-Null
$library=Split-Path (Split-Path (Split-Path $found));$vdf='"libraryfolders" { "0" { "path" "'+$steam.Replace('\','\\')+'" } "1" { "path" "'+$library.Replace('\','\\')+'" } }'
[IO.File]::WriteAllText((Join-Path $steam 'steamapps\libraryfolders.vdf'),$vdf)
$savedRoots=${function:Get-HuSteamRoots};$script:testSteam=$steam;function Get-HuSteamRoots{$script:testSteam}
try{Check ((Find-HuGame) -eq $found) 'automatic Steam detection finds additional VDF library'}finally{Set-Item function:Get-HuSteamRoots $savedRoots}
[IO.File]::WriteAllText((Join-Path $steam 'steamapps\libraryfolders.vdf'),('"LibraryFolders" { "1" "'+$library.Replace('\','\\')+'" }'))
function Get-HuSteamRoots{$script:testSteam}
try{Check ((Find-HuGame) -eq $found) 'automatic Steam detection also accepts legacy VDF library entries'}finally{Set-Item function:Get-HuSteamRoots $savedRoots}
$manifest=Join-Path (Split-Path (Split-Path $found)) 'appmanifest_286690.acf'
[IO.File]::WriteAllText($manifest,'"AppState" { "appid" "287390" "StateFlags" "4" "installdir" "MetroFixture" }')
Rejected {Assert-HuGame $found} 'NOT_STEAM' 'Last Light app ID is rejected'
[pscustomobject]@{Passed=$checks.Count;GameDirectoryModified=$false;TemporaryFilesRemovedOnExit=$true}
}finally{Remove-HuScratch $testRoot $scratchParent 'metro2033-components-'}

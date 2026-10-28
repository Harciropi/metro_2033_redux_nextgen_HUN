param(
 [ValidateSet('Detect','Install','Remove')][string]$Mode='Detect',
 [string]$GameDir=$env:METRO_HU_GAME_DIR,
 [string]$PayloadDir=([IO.Path]::Combine($PSScriptRoot,'payload')),
 [string]$ReportPath=$env:METRO_HU_REPORT,
 [switch]$LibraryOnly
)
$HuOriginal='02DA3140038E10705252538240B54D10A8C1A79A7778A4B10E564A7F695A78F8'
$HuIndex='80B271519B9577DF550A4EA26D466C910533EA5C967E8190D8F9AA52F2F3A41D'
$HuOldIndexes=@('794700A12A2597FEEBCFECE5F0CA08749C3B45632750AC9F415B16B69BFA56EE','B60BF8F2851BE2D6528E5A4B2CD5EE4F8FF95FBF51CB592E5C7CAC5E6E6852BF','A3E2A986A515606DF6AE1047A80238C7D120B8F0D75C348B50488E776F56D24F','6A608902B944160CD72468FE3D798D0ACE7A647B0C8DF3D5E18CCBB64D8B2B23','E9DFF95E78106B487842FE35AE945BCAAB664522C9B6C2B883B501AAA092BEF6')
$HuArchive='0B89A1E1DC7C24005C841A76E4827316E099386E11D83158FF6919478B6B94F6'

$HuOldArchives=@('74860253804313F07E696E50EE4002A6F70A336E518981D544F5E2CD76548127','79FA3227DAB1C56B25005825B41D3825BA8761557193676ACECC8FB912E93494','CC8F6084CD65F4D1EAA370DDFF518E928B26AE1A09C7619D76832B03608A0981','DCA8F96A73690F0CF408C19D8EB645131C1BF177FC2C79C176EE9C73311F0227','F08F239397E3CA975AE2DE520118EE232BD80EDAA1F00A5DF818E8159E1885A9','900CB34D9BE66D00BBC8D995862FBF2D051FE5DE98CA7D9E64B2B531AA56BFB3','1B307FF77E83333C065C38C0F02E1ED22BDE9C38B998FE4D8D0D13054BB6C9A8')
$HuArchiveName='content_hun_nextgen2.vfs0'
$HuBackupName='Magyaritas_NextGen_20261022'
function Get-HuHash([string]$Path){
 if(-not [IO.File]::Exists($Path)){return 'MISSING'}
 $stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
}
function Assert-HuPayload([string]$Folder){
 if((Get-HuHash ([IO.Path]::Combine($Folder,'original-content.vfx'))) -ne $HuOriginal -or (Get-HuHash ([IO.Path]::Combine($Folder,'content.vfx'))) -ne $HuIndex -or (Get-HuHash ([IO.Path]::Combine($Folder,$HuArchiveName))) -ne $HuArchive){throw 'BAD_PACKAGE'}
}
function Test-HuSteamNextGen([string]$Folder){
 if(-not [IO.File]::Exists([IO.Path]::Combine($Folder,'steam_api64.dll'))){return $false}
 $nextGen=$false
 foreach($name in @('nvngx_dlss.dll','nvngx_dlssnr.dll','amd_fidelityfx_dx12.dll')){if([IO.File]::Exists([IO.Path]::Combine($Folder,$name))){$nextGen=$true;break}}
 if(-not $nextGen){return $false}
 $parent=[IO.Directory]::GetParent($Folder)
 if($null -ne $parent -and $parent.Name -ieq 'common'){
  $steamapps=$parent.Parent
  if($null -ne $steamapps){
   $manifest=[IO.Path]::Combine($steamapps.FullName,'appmanifest_286690.acf')
   if([IO.File]::Exists($manifest) -and [IO.File]::ReadAllText($manifest) -notmatch '"appid"\s+"286690"'){return $false}
  }
 }
 return $true
}
function Get-HuState([string]$Folder){
 if([string]::IsNullOrWhiteSpace($Folder)){return 'NOT_GAME'}
 $exe=[IO.Path]::Combine($Folder,'metro.exe');$index=[IO.Path]::Combine($Folder,'content.vfx');$archive=[IO.Path]::Combine($Folder,$HuArchiveName)
 if(-not [IO.File]::Exists($exe) -or -not [IO.File]::Exists($index)){return 'NOT_GAME'}
 if(-not (Test-HuSteamNextGen $Folder)){return 'WRONG_VERSION'}
 foreach($process in [Diagnostics.Process]::GetProcessesByName('metro')){
  try{if([string]::Equals($process.MainModule.FileName,$exe,[StringComparison]::OrdinalIgnoreCase)){return 'GAME_RUNNING'}}catch{return 'GAME_RUNNING'}finally{$process.Dispose()}
 }
 $ih=Get-HuHash $index;$ah=Get-HuHash $archive
 if($ah -ne 'MISSING' -and $ah -ne $HuArchive -and $HuOldArchives -notcontains $ah){return 'FILE_CONFLICT'}
 if($ih -eq $HuIndex -and $ah -eq $HuArchive){return 'READY_REMOVE'}
 if($ih -eq $HuIndex -or $HuOldIndexes -contains $ih){if($ah -eq 'MISSING'){return 'READY_REPAIR'};return 'READY_UPGRADE'}
 # Nem a magyarítás által írt jegyzék: bármely Steam next-gen build telepíthető.
 return 'READY_INSTALL'
}
function Get-HuBackup([string]$Folder){
 $backup=[IO.Path]::Combine($Folder,$HuBackupName);$marker=[IO.Path]::Combine($backup,'allapot.ini')
 if([IO.File]::Exists($marker)){
  $fields=@{}
  foreach($line in [IO.File]::ReadAllLines($marker)){if($line -match '^([^=]+)=(.*)$'){$fields[$matches[1]]=$matches[2]}}
  if($fields.ContainsKey('OriginalFile')){
   if($fields['OriginalFile'] -notmatch '^eredeti-[a-fA-F0-9]{32}\.vfx$' -or $fields['OriginalHash'] -notmatch '^[a-fA-F0-9]{64}$'){throw 'BACKUP_CONFLICT'}
   $path=[IO.Path]::Combine($backup,$fields['OriginalFile']);$hash=Get-HuHash $path
   if($hash -ne $fields['OriginalHash']){throw 'BACKUP_CONFLICT'}
   return [pscustomobject]@{Path=$path;Hash=$hash}
  }
 }
 $legacy=[IO.Path]::Combine($backup,'content.vfx')
 if([IO.File]::Exists($legacy)){return [pscustomobject]@{Path=$legacy;Hash=(Get-HuHash $legacy)}}
 return $null
}
function Invoke-HuInstall([string]$Folder,[string]$Payload){
 Assert-HuPayload $Payload
 $state=Get-HuState $Folder
 if(@('READY_INSTALL','READY_UPGRADE','READY_REPAIR') -notcontains $state){throw $state}
 $index=[IO.Path]::Combine($Folder,'content.vfx');$archive=[IO.Path]::Combine($Folder,$HuArchiveName)
 $beforeIndex=[IO.File]::ReadAllBytes($index);$beforeArchive=$null
 if([IO.File]::Exists($archive)){$beforeArchive=[IO.File]::ReadAllBytes($archive)}
 $backup=[IO.Path]::Combine($Folder,$HuBackupName);[IO.Directory]::CreateDirectory($backup)|Out-Null
 $name='eredeti-'+[guid]::NewGuid().ToString('N')+'.vfx';$backupIndex=[IO.Path]::Combine($backup,$name)
 if($state -eq 'READY_UPGRADE' -or $state -eq 'READY_REPAIR'){
  $existing=Get-HuBackup $Folder
  if($null -ne $existing){[IO.File]::Copy($existing.Path,$backupIndex,$false)}else{[IO.File]::Copy([IO.Path]::Combine($Payload,'original-content.vfx'),$backupIndex,$false)}
 }else{[IO.File]::WriteAllBytes($backupIndex,$beforeIndex)}
 $originalHash=Get-HuHash $backupIndex
 $marker=[IO.Path]::Combine($backup,'allapot.ini');$previousMarker=$null
 if([IO.File]::Exists($marker)){$previousMarker=[IO.File]::ReadAllBytes($marker)}
 try{
  if((Get-HuState $Folder) -ne $state){throw 'STATE_CHANGED'}
  [IO.File]::Copy([IO.Path]::Combine($Payload,$HuArchiveName),$archive,$true)
  [IO.File]::Copy([IO.Path]::Combine($Payload,'content.vfx'),$index,$true)
  if((Get-HuHash $index) -ne $HuIndex -or (Get-HuHash $archive) -ne $HuArchive){throw 'COPY_FAILED'}
  [IO.File]::WriteAllText($marker,"[Magyaritas]`r`nVersion=1.5.3`r`nOriginalFile=$name`r`nOriginalHash=$originalHash`r`n",[Text.Encoding]::Unicode)
 }catch{
  try{
   if($null -eq $beforeArchive){if([IO.File]::Exists($archive)){[IO.File]::Delete($archive)}}else{[IO.File]::WriteAllBytes($archive,$beforeArchive)}
   [IO.File]::WriteAllBytes($index,$beforeIndex)
   if($null -ne $previousMarker){[IO.File]::WriteAllBytes($marker,$previousMarker)}elseif([IO.File]::Exists($marker)){[IO.File]::Delete($marker)}
  }catch{throw 'RESTORE_FAILED'}
  throw
 }
 return 'INSTALLED'
}
function Invoke-HuRemove([string]$Folder,[string]$Payload){
 Assert-HuPayload $Payload
 $state=Get-HuState $Folder
 if($state -ne 'READY_REMOVE'){throw $state}
 $index=[IO.Path]::Combine($Folder,'content.vfx');$archive=[IO.Path]::Combine($Folder,$HuArchiveName)
 $beforeIndex=[IO.File]::ReadAllBytes($index);$beforeArchive=[IO.File]::ReadAllBytes($archive)
 $original=Get-HuBackup $Folder
 if($null -eq $original){$original=[pscustomobject]@{Path=[IO.Path]::Combine($Payload,'original-content.vfx');Hash=$HuOriginal}}
 try{
  if((Get-HuState $Folder) -ne 'READY_REMOVE'){throw 'STATE_CHANGED'}
  [IO.File]::Copy($original.Path,$index,$true)
  if((Get-HuHash $index) -ne $original.Hash){throw 'COPY_FAILED'}
  if((Get-HuHash $archive) -ne $HuArchive){throw 'STATE_CHANGED'}
  [IO.File]::Delete($archive)
 }catch{
  try{[IO.File]::WriteAllBytes($archive,$beforeArchive);[IO.File]::WriteAllBytes($index,$beforeIndex)}catch{throw 'RESTORE_FAILED'}
  throw
 }
 # Kizárólag a saját mentés és állapotjelző törölhető; idegen fájlok megmaradnak.
 try{
  $backup=[IO.Path]::Combine($Folder,$HuBackupName)
  if([string]::Equals([IO.Path]::GetDirectoryName($original.Path),$backup,[StringComparison]::OrdinalIgnoreCase) -and (Get-HuHash $original.Path) -eq $original.Hash){[IO.File]::Delete($original.Path)}
  $marker=[IO.Path]::Combine($backup,'allapot.ini')
  if([IO.File]::Exists($marker)){
   $content=[IO.File]::ReadAllText($marker)
   if($content -match '^\[Magyaritas\]\r?\nVersion=1\.[45](?:\.\d+)?\r?\n'){[IO.File]::Delete($marker)}
  }
  if([IO.Directory]::Exists($backup) -and [IO.Directory]::GetFileSystemEntries($backup).Length -eq 0){[IO.Directory]::Delete($backup,$false)}
 }catch{}
 return 'REMOVED'
}
function Write-HuReport([string]$Path,[string]$State){
 if(-not [string]::IsNullOrWhiteSpace($Path)){[IO.File]::WriteAllText($Path,"[Result]`r`nState=$State`r`n",[Text.Encoding]::Unicode)}
}
if(-not $LibraryOnly){
 try{
  $GameDir=[IO.Path]::GetFullPath($GameDir)
  Assert-HuPayload $PayloadDir
  if($Mode -eq 'Install'){$result=Invoke-HuInstall $GameDir $PayloadDir}
  elseif($Mode -eq 'Remove'){$result=Invoke-HuRemove $GameDir $PayloadDir}
  else{$result=Get-HuState $GameDir}
  Write-HuReport $ReportPath $result
  [Console]::WriteLine($result)
  if($result.StartsWith('READY_') -or $result -eq 'INSTALLED' -or $result -eq 'REMOVED'){exit 0}else{exit 1}
 }catch{
  $code=$_.Exception.Message
  if(@('BAD_PACKAGE','BACKUP_CONFLICT','STATE_CHANGED','COPY_FAILED','RESTORE_FAILED','NOT_GAME','WRONG_VERSION','GAME_RUNNING','FILE_CONFLICT','WRONG_FILES','READY_REMOVE') -notcontains $code){$code='OPERATION_FAILED'}
  Write-HuReport $ReportPath $code
  [Console]::WriteLine($code)
  exit 1
 }
}
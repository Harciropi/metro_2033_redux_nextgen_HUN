param(
 [ValidateSet('Detect','Install','Apply','Remove')][string]$Mode='Detect',
 [string]$GameDir,
 [string]$PayloadDir=(Join-Path $PSScriptRoot 'payload'),
 [string]$ReportPath,
 [string]$Components,
 [switch]$LibraryOnly
)
$ErrorActionPreference='Stop'
$TrustedManifestHash='@@MANIFEST_SHA256@@'
$HuProduct='Harciropi.Metro2033Redux.NextGen.HU'
$HuArchive='content_hun_nextgen2.vfs0'
$HuBackup='Magyaritas_NextGen_20261022'
function Get-HuHash([string]$Path){
 if(-not [IO.File]::Exists($Path)){return 'MISSING'}
 $h=[Security.Cryptography.SHA256]::Create();$s=[IO.File]::OpenRead($Path)
 try{return [BitConverter]::ToString($h.ComputeHash($s)).Replace('-','')}finally{$s.Dispose();$h.Dispose()}
}
function Assert-HuRegular([string]$Path){
 if(Test-Path -LiteralPath $Path){if(((Get-Item -Force -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'FILE_CONFLICT'}}
}
function Read-HuPackage([string]$Folder){
 $manifest=Join-Path $Folder 'package.json'
 if((Get-HuHash $manifest) -ne $TrustedManifestHash){throw 'BAD_PACKAGE'}
 $p=[IO.File]::ReadAllText($manifest)|ConvertFrom-Json
 if($p.Product -ne $HuProduct -or $p.Version -notmatch '^\d+\.\d+\.\d+$'){throw 'BAD_PACKAGE'}
 $expected=@('content.vfx','content_hun_nextgen2.vfs0','original-content.vfx','Resources.cs');$names=@{}
 foreach($f in @($p.Files)){
  if($expected -notcontains $f.Name -or $names.ContainsKey($f.Name) -or $f.Sha256 -notmatch '^[A-F0-9]{64}$'){throw 'BAD_PACKAGE'}
  $names[$f.Name]=$true;$path=Join-Path $Folder $f.Name;Assert-HuRegular $path
  if((Get-HuHash $path) -ne $f.Sha256){throw 'BAD_PACKAGE'}
 }
 if($names.Count -ne $expected.Count){throw 'BAD_PACKAGE'}
 if(-not ('Metro2033Hu.ResourceIndex' -as [type])){Add-Type -Path (Join-Path $Folder 'Resources.cs')}
 return $p
}

function Get-HuFolder([string]$Folder){
 if([string]::IsNullOrWhiteSpace($Folder)){throw 'NOT_GAME'}
 return [IO.Path]::GetFullPath($Folder).TrimEnd('\','/')
}
function Get-HuSteamRoots(){
 foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')){
  $item=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
  if($null -ne $item){foreach($name in @('SteamPath','InstallPath')){$v=$item.$name;if(-not [string]::IsNullOrWhiteSpace($v)){$v}}}
 }
}
function Find-HuGame(){
 $libraries=[Collections.Generic.List[string]]::new();$seen=@{}
 foreach($root in @(Get-HuSteamRoots)){
  try{$root=Get-HuFolder $root}catch{continue}
  if(-not $seen.ContainsKey($root)){$seen[$root]=$true;$libraries.Add($root)}
  $vdf=Join-Path $root 'steamapps\libraryfolders.vdf'
  if([IO.File]::Exists($vdf)){
   $text=[IO.File]::ReadAllText($vdf)
   foreach($m in [regex]::Matches($text,'"(?:path|\d+)"\s+"([^"]+)"')){
    $value=$m.Groups[1].Value.Replace('\\','\')
    if(-not [IO.Path]::IsPathRooted($value)){continue}
    try{$value=Get-HuFolder $value}catch{continue}
    if(-not $seen.ContainsKey($value)){$seen[$value]=$true;$libraries.Add($value)}
   }
  }
 }
 foreach($library in $libraries){
  $manifest=Join-Path $library 'steamapps\appmanifest_286690.acf'
  if(-not [IO.File]::Exists($manifest)){continue}
  $text=[IO.File]::ReadAllText($manifest)
  if($text -match '"installdir"\s+"([^"\\/]+)"' -and $matches[1] -notin @('.','..')){
   $candidate=Get-HuFolder (Join-Path $library ('steamapps\common\'+$matches[1]))
   try{Assert-HuGame $candidate|Out-Null;return $candidate}catch{if($_.Exception.Message -eq 'GAME_RUNNING'){throw}}
  }
 }
 throw 'NOT_GAME'
}

function Assert-HuGame([string]$Folder){
 foreach($name in @('metro.exe','content.vfx','steam_api64.dll')){if(-not [IO.File]::Exists((Join-Path $Folder $name))){throw 'NOT_GAME'};Assert-HuRegular (Join-Path $Folder $name)}
 if(-not ([IO.File]::Exists((Join-Path $Folder 'nvngx_dlssnr.dll')) -or [IO.File]::Exists((Join-Path $Folder 'amd_fidelityfx_dx12.dll')) -or [IO.File]::Exists((Join-Path $Folder 'nvngx_dlss.dll')))){throw 'WRONG_VERSION'}
 $common=[IO.Directory]::GetParent($Folder)
 if($null -eq $common -or $common.Name -ine 'common' -or $null -eq $common.Parent){throw 'NOT_STEAM'}
 $manifest=Join-Path $common.Parent.FullName 'appmanifest_286690.acf'
 if(-not [IO.File]::Exists($manifest)){throw 'NOT_STEAM'}
 $text=[IO.File]::ReadAllText($manifest)
 if($text -notmatch '"StateFlags"\s+"4"' -or $text -notmatch '"appid"\s+"286690"' -or $text -notmatch '"installdir"\s+"([^"\\/]+)"'){throw 'NOT_STEAM'}
 if($matches[1] -ine [IO.Path]::GetFileName($Folder)){throw 'NOT_STEAM'}
 if($text -match '"betakey"\s+"[^"]*legacy[^"]*"'){throw 'WRONG_VERSION'}
 try{$index=[Metro2033Hu.ResourceIndex]::new([IO.File]::ReadAllBytes((Join-Path $Folder 'content.vfx')))}catch{throw 'UNSUPPORTED_LAYOUT'}
 if(-not $index.Files.ContainsKey('content/maps/2033/l36_ostankino/level.bin') -or -not $index.Files.ContainsKey('content/maps/2033/l23_polis/level.bin') -or -not $index.Archives.Contains('content00.vfs2')){throw 'WRONG_VERSION'}
 foreach($process in [Diagnostics.Process]::GetProcessesByName('metro')){
  try{if([string]::Equals($process.MainModule.FileName,(Join-Path $Folder 'metro.exe'),[StringComparison]::OrdinalIgnoreCase)){throw 'GAME_RUNNING'}}catch{throw 'GAME_RUNNING'}finally{$process.Dispose()}
 }
 return $index
}

function Get-HuInstalledComponents($State){
 if($null -eq $State){return}
 if($null -eq $State.PSObject.Properties['Components']){return 'Translation'}
 $items=@($State.Components)
 if($items.Count -eq 0 -or @($items|Where-Object {$_ -notin @('Translation','HideAds')}).Count -gt 0 -or @($items|Select-Object -Unique).Count -ne $items.Count){throw 'STATE_CONFLICT'}
 foreach($name in @('Translation','HideAds')){if($items -contains $name){$name}}
}
function Resolve-HuComponents([string]$Selection,$Previous){
 if([string]::IsNullOrWhiteSpace($Selection)){if($null -eq $Previous){return 'Translation'};Get-HuInstalledComponents $Previous;return}
 if($Selection -eq 'None'){return}
 $items=@($Selection.Split(','))
 if(@($items|Where-Object {$_ -cnotin @('Translation','HideAds')}).Count -gt 0 -or @($items|Select-Object -Unique).Count -ne $items.Count){throw 'BAD_COMPONENTS'}
 foreach($name in @('Translation','HideAds')){if($items -contains $name){$name}}
}
function Format-HuComponents($Items){if(@($Items).Count -eq 0){return 'None'};return (@($Items)-join ',')}
function Get-HuBytesHash([byte[]]$Bytes){$h=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($h.ComputeHash($Bytes)).Replace('-','')}finally{$h.Dispose()}}
$LegacyIndexes=@('80B271519B9577DF550A4EA26D466C910533EA5C967E8190D8F9AA52F2F3A41D','794700A12A2597FEEBCFECE5F0CA08749C3B45632750AC9F415B16B69BFA56EE','B60BF8F2851BE2D6528E5A4B2CD5EE4F8FF95FBF51CB592E5C7CAC5E6E6852BF','A3E2A986A515606DF6AE1047A80238C7D120B8F0D75C348B50488E776F56D24F','6A608902B944160CD72468FE3D798D0ACE7A647B0C8DF3D5E18CCBB64D8B2B23','E9DFF95E78106B487842FE35AE945BCAAB664522C9B6C2B883B501AAA092BEF6')
$LegacyArchives=@('0B89A1E1DC7C24005C841A76E4827316E099386E11D83158FF6919478B6B94F6','74860253804313F07E696E50EE4002A6F70A336E518981D544F5E2CD76548127','79FA3227DAB1C56B25005825B41D3825BA8761557193676ACECC8FB912E93494','CC8F6084CD65F4D1EAA370DDFF518E928B26AE1A09C7619D76832B03608A0981','DCA8F96A73690F0CF408C19D8EB645131C1BF177FC2C79C176EE9C73311F0227','F08F239397E3CA975AE2DE520118EE232BD80EDAA1F00A5DF818E8159E1885A9','900CB34D9BE66D00BBC8D995862FBF2D051FE5DE98CA7D9E64B2B531AA56BFB3','1B307FF77E83333C065C38C0F02E1ED22BDE9C38B998FE4D8D0D13054BB6C9A8')
$LegacyOriginal='02DA3140038E10705252538240B54D10A8C1A79A7778A4B10E564A7F695A78F8'
function Read-HuLegacyState([string]$Folder){
 $ih=Get-HuHash (Join-Path $Folder 'content.vfx')
 if($LegacyIndexes -notcontains $ih){return $null}
 $ah=Get-HuHash (Join-Path $Folder $HuArchive)
 if($ah -ne 'MISSING' -and $LegacyArchives -notcontains $ah){throw 'FILE_CONFLICT'}
 $backup=Join-Path $Folder $HuBackup;$marker=Join-Path $backup 'allapot.ini';Assert-HuRegular $marker
 $name='content.vfx';$hash=$LegacyOriginal;$version='1.5.3'
 if([IO.File]::Exists($marker)){
  $fields=@{};foreach($line in [IO.File]::ReadAllLines($marker)){if($line -match '^([^=]+)=(.*)$'){$fields[$matches[1]]=$matches[2]}}
  if($fields.Version -notmatch '^1\.[45](?:\.\d+)?$' -or $fields.OriginalHash -notmatch '^[A-Fa-f0-9]{64}$' -or $fields.OriginalFile -notmatch '^eredeti-[A-Fa-f0-9]{32}\.vfx$'){throw 'BACKUP_CONFLICT'}
  $name=$fields.OriginalFile;$hash=$fields.OriginalHash.ToUpperInvariant();$version=$fields.Version
 }
 $original=Join-Path $backup $name;Assert-HuRegular $original
 if((Get-HuHash $original) -ne $hash){throw 'BACKUP_CONFLICT'}
 return [pscustomobject]@{Product=$HuProduct;Version=$version;Components=@('Translation');OriginalName=$name;OriginalHash=$hash;IndexHash=$ih;ArchiveHash=$ah;PackageHash=('0'*64);SdkOriginalName=$null;SdkOriginalHash=$null;SdkHash='MISSING';Legacy=$true}
}
function Read-HuState([string]$Folder){
 $backup=Join-Path $Folder $HuBackup;Assert-HuRegular $backup
 $file=Join-Path $backup 'state.json';Assert-HuRegular $file
 if(-not [IO.File]::Exists($file)){return Read-HuLegacyState $Folder}
 try{$s=[IO.File]::ReadAllText($file)|ConvertFrom-Json}catch{throw 'STATE_CONFLICT'}
 if($s.Product -ne $HuProduct -or $s.Version -notmatch '^\d+\.\d+\.\d+$' -or $s.OriginalName -notmatch '^(original-[a-f0-9]{32}|eredeti-[A-Fa-f0-9]{32}|content)\.vfx$'){throw 'STATE_CONFLICT'}
 foreach($hash in @($s.OriginalHash,$s.IndexHash,$s.PackageHash)){if($hash -notmatch '^[A-F0-9]{64}$'){throw 'STATE_CONFLICT'}}
 $components=@(Get-HuInstalledComponents $s)
 if($components -contains 'Translation'){if($s.ArchiveHash -notmatch '^[A-F0-9]{64}$'){throw 'STATE_CONFLICT'}}elseif($s.ArchiveHash -ne 'MISSING'){throw 'STATE_CONFLICT'}
 $original=Join-Path $backup $s.OriginalName;Assert-HuRegular $original
 if((Get-HuHash $original) -ne $s.OriginalHash){throw 'BACKUP_CONFLICT'}
 if($components -contains 'HideAds'){
  if($s.SdkOriginalName -notmatch '^sdk-original-[A-F0-9]{64}\.dll$' -or $s.SdkOriginalHash -notmatch '^[A-F0-9]{64}$' -or $s.SdkHash -notmatch '^[A-F0-9]{64}$'){throw 'STATE_CONFLICT'}
  $sdkBackup=Join-Path $backup $s.SdkOriginalName;Assert-HuRegular $sdkBackup
  if((Get-HuHash $sdkBackup) -ne $s.SdkOriginalHash){throw 'BACKUP_CONFLICT'}
 }
 return $s
}
function Assert-HuSdkOriginal([string]$Folder){
 $path=Join-Path $Folder 'pros.sdk.x64.dll';Assert-HuRegular $path
 if(-not [IO.File]::Exists($path)){throw 'BANNER_UNSUPPORTED'}
 try{$kind=[Metro2033Hu.BannerFilter]::Inspect([IO.File]::ReadAllBytes($path))}catch{throw 'BANNER_UNSUPPORTED'}
 if($kind -ne 'ORIGINAL'){throw 'FILE_CONFLICT'}
}
function Get-HuState([string]$Folder,$Package,[string]$Selection){
 $index=Assert-HuGame $Folder;$backup=Join-Path $Folder $HuBackup
 Assert-HuRegular $backup;Assert-HuRegular (Join-Path $Folder $HuArchive)
 if([IO.File]::Exists((Join-Path $backup 'pending.json'))){throw 'RECOVERY_NEEDED'}
 $s=Read-HuState $Folder;$selected=@(Resolve-HuComponents $Selection $s)
 $script:HuDetectedComponents=Format-HuComponents @(Get-HuInstalledComponents $s)
 $script:HuDetectedVersion=if($null -ne $s){$s.Version}else{''}
 $ah=Get-HuHash (Join-Path $Folder $HuArchive);$ih=Get-HuHash (Join-Path $Folder 'content.vfx')
 if($null -ne $s){
  if([version]$s.Version -gt [version]$Package.Version){throw 'NEWER_INSTALLED'}
  if($ah -ne $s.ArchiveHash){throw 'FILE_CONFLICT'}
  $installed=@(Get-HuInstalledComponents $s);$rebase=$false
  if($ih -ne $s.IndexHash){
   if($index.Archives.Contains($HuArchive)){throw 'FILE_CONFLICT'}
   Assert-HuSourceTargets $index $Package $selected;$rebase=$true
  }elseif(($installed -contains 'Translation') -ne $index.Archives.Contains($HuArchive)){throw 'STATE_CONFLICT'}
  if($installed -contains 'HideAds'){
   $sdkPath=Join-Path $Folder 'pros.sdk.x64.dll';Assert-HuRegular $sdkPath
   if((Get-HuHash $sdkPath) -ne $s.SdkHash){Assert-HuSdkOriginal $Folder;$rebase=$true}
  }elseif($selected -contains 'HideAds'){Assert-HuSdkOriginal $Folder}
  if($rebase){return 'READY_REBASE'}
  if([version]$s.Version -eq [version]$Package.Version){if($s.PackageHash -ne $TrustedManifestHash){return 'READY_UPGRADE'};return 'READY_REMOVE'}
  return 'READY_UPGRADE'
 }
 if($ah -ne 'MISSING' -or $index.Archives.Contains($HuArchive)){throw 'FILE_CONFLICT'}
 Assert-HuSourceTargets $index $Package $selected
 if($selected -contains 'HideAds'){Assert-HuSdkOriginal $Folder}
 return 'READY_INSTALL'
}
function Assert-HuSourceTargets($Index,$Package,$Selection=@('Translation')){
 if($Selection -contains 'Translation'){
  $resource='content/localization/stable_us.lng'
  if(-not $Index.Files.ContainsKey($resource)){throw 'UNSUPPORTED_LAYOUT'}
  if($Index.Archives[$Index.Files[$resource].Archive] -notmatch '^content\d{2}\.vfs\d$'){throw 'FILE_CONFLICT'}
 }
}

function Write-HuJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
function Write-HuAtomic([string]$Path,[byte[]]$Bytes){
 [Metro2033Hu.ResourceIndex]::AtomicWrite($Path,$Bytes)
}
function New-HuOverlay([string]$Folder,[byte[]]$BaseIndex,$Package,[string]$Payload){
 $index=[Metro2033Hu.ResourceIndex]::new($BaseIndex);Assert-HuSourceTargets $index $Package @('Translation')
 $template=[Metro2033Hu.ResourceIndex]::new([IO.File]::ReadAllBytes((Join-Path $Payload 'content.vfx')))
 $resources=[string[]]@('content/localization/stable_us.lng');$contents=[byte[][]]::new(1)
 $contents[0]=$template.Extract($Payload,$resources[0])
 $overlay=$index.Overlay($HuArchive,$resources,$contents)
 return [pscustomobject]@{Index=$overlay[0];Archive=$overlay[1]}
}

function Remove-HuRestoredBackups([string]$Folder,[string]$Backup){
 $expected=[IO.Path]::GetFullPath((Join-Path (Get-HuFolder $Folder) $HuBackup))
 if(-not [string]::Equals([IO.Path]::GetFullPath($Backup),$expected,[StringComparison]::OrdinalIgnoreCase)){throw 'CLEANUP_FAILED'}
 Assert-HuRegular $Backup
 foreach($path in [IO.Directory]::GetFiles($Backup)){
  $name=[IO.Path]::GetFileName($path);$owned=$name -cmatch '^((?:original|eredeti)-[a-fA-F0-9]{32}\.vfx|sdk-original-[A-F0-9]{64}\.dll|history-[a-f0-9]{32}\.json)$'
  if($name -ceq 'content.vfx' -and (Get-HuHash $path) -eq $LegacyOriginal){$owned=$true}
  if($name -ceq 'allapot.ini'){
   $s=[IO.File]::ReadAllText($path)
   $owned=$s -match '^\[Magyaritas\]\r?\nVersion=1\.[45](?:\.\d+)?\r?\nOriginalFile=eredeti-[A-Fa-f0-9]{32}\.vfx\r?\nOriginalHash=[A-Fa-f0-9]{64}\r?\n?$'
  }
  if($owned){try{Assert-HuRegular $path;[IO.File]::Delete($path)}catch{throw 'CLEANUP_FAILED'}}
 }
}

function Invoke-HuOperation([string]$Folder,$Package,[string]$Payload,[string]$Operation,[string]$Selection){
 $before=Get-HuState $Folder $Package $Selection;$previous=Read-HuState $Folder
 if($Operation -eq 'Remove'){
  if($null -eq $previous){throw $before};$selected=@()
 }else{
  $selected=@(Resolve-HuComponents $Selection $previous)
  if($selected.Count -eq 0){throw 'NO_COMPONENTS'}
  if($Operation -eq 'Install' -and @('READY_INSTALL','READY_UPGRADE','READY_REBASE') -notcontains $before){throw $before}
  if($Operation -eq 'Apply' -and $before -eq 'READY_REMOVE' -and (Format-HuComponents $selected) -eq (Format-HuComponents @(Get-HuInstalledComponents $previous))){return 'UNCHANGED'}
 }
 $backup=Join-Path $Folder $HuBackup;[IO.Directory]::CreateDirectory($backup)|Out-Null;Assert-HuRegular $backup
 $lockPath=Join-Path $backup 'operation.lock';Assert-HuRegular $lockPath
 try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'OPERATION_BUSY'}
 $cleanupCompleted=$false
 try{
  if((Get-HuState $Folder $Package $Selection) -ne $before){throw 'STATE_CHANGED'}
  $indexPath=Join-Path $Folder 'content.vfx';$archivePath=Join-Path $Folder $HuArchive;$statePath=Join-Path $backup 'state.json';$sdkPath=Join-Path $Folder 'pros.sdk.x64.dll'
  $previous=Read-HuState $Folder;$was=@(Get-HuInstalledComponents $previous)
  $manageSdk=($was -contains 'HideAds' -or $selected -contains 'HideAds')
  $targets=@($archivePath,$indexPath);if($manageSdk){$targets+=@($sdkPath)};$targets+=@($statePath)
  $old=@{};$hashes=@{}
  foreach($path in $targets){Assert-HuRegular $path;$hashes[$path]=Get-HuHash $path;$old[$path]=$null;if($hashes[$path] -ne 'MISSING'){$old[$path]=[IO.File]::ReadAllBytes($path)}}
  if($null -ne $previous -and $hashes[$indexPath] -eq $previous.IndexHash){
   $originalName=$previous.OriginalName;$originalHash=$previous.OriginalHash;$base=[IO.File]::ReadAllBytes((Join-Path $backup $originalName))
  }else{
   $base=$old[$indexPath];$originalHash=Get-HuBytesHash $base;$originalName='original-'+[guid]::NewGuid().ToString('N')+'.vfx';$originalPath=Join-Path $backup $originalName
   [IO.File]::WriteAllBytes($originalPath,$base);if((Get-HuHash $originalPath) -ne $originalHash){throw 'BACKUP_CONFLICT'}
  }
  $nextIndex=$base;$nextArchive=$null
  if($selected -contains 'Translation'){
   $source=[Metro2033Hu.ResourceIndex]::new($base);Assert-HuSourceTargets $source $Package $selected
   $overlay=New-HuOverlay $Folder $base $Package $Payload;$nextIndex=$overlay.Index;$nextArchive=$overlay.Archive
  }
  $sdkOriginalName=$null;$sdkOriginalHash=$null;$nextSdk=$null
  if($manageSdk){
   if($was -contains 'HideAds' -and $hashes[$sdkPath] -eq $previous.SdkHash){$sdkBase=[IO.File]::ReadAllBytes((Join-Path $backup $previous.SdkOriginalName))}
   else{Assert-HuSdkOriginal $Folder;$sdkBase=$old[$sdkPath]}
   $nextSdk=$sdkBase
   if($selected -contains 'HideAds'){
    $sdkOriginalHash=Get-HuBytesHash $sdkBase;$sdkOriginalName='sdk-original-'+$sdkOriginalHash+'.dll';$save=Join-Path $backup $sdkOriginalName;Assert-HuRegular $save
    if(-not [IO.File]::Exists($save)){[IO.File]::WriteAllBytes($save,$sdkBase)}
    if((Get-HuHash $save) -ne $sdkOriginalHash){throw 'BACKUP_CONFLICT'}
    $nextSdk=[Metro2033Hu.BannerFilter]::Apply($sdkBase)
   }
  }
  $nextState=$null
  if($selected.Count -gt 0){
   $nextState=[ordered]@{Product=$HuProduct;Version=$Package.Version;Components=@($selected);OriginalName=$originalName;OriginalHash=$originalHash;IndexHash=(Get-HuBytesHash $nextIndex);ArchiveHash=if($null -ne $nextArchive){Get-HuBytesHash $nextArchive}else{'MISSING'};PackageHash=$TrustedManifestHash;SdkOriginalName=$sdkOriginalName;SdkOriginalHash=$sdkOriginalHash;SdkHash=if($selected -contains 'HideAds'){Get-HuBytesHash $nextSdk}else{'MISSING'}}
  }
  if($null -ne $old[$statePath]){[IO.File]::WriteAllBytes((Join-Path $backup ('history-'+[guid]::NewGuid().ToString('N')+'.json')),$old[$statePath])}
  $next=@{};$next[$indexPath]=$nextIndex;$next[$archivePath]=$nextArchive;if($manageSdk){$next[$sdkPath]=$nextSdk};$next[$statePath]=if($null -ne $nextState){[Text.UTF8Encoding]::new($false).GetBytes(($nextState|ConvertTo-Json -Depth 8))}else{$null}
  $pending=Join-Path $backup 'pending.json';Write-HuJson $pending ([ordered]@{Product=$HuProduct;Operation=$Operation;Components=@($selected);Before=$hashes;OriginalName=$originalName;SdkOriginalName=$sdkOriginalName})
  foreach($path in $targets){if((Get-HuHash $path) -ne $hashes[$path]){[IO.File]::Delete($pending);throw 'STATE_CHANGED'}}
  try{
   foreach($path in $targets){
    $expected=if($null -ne $next[$path]){Get-HuBytesHash $next[$path]}else{'MISSING'}
    if((Get-HuHash $path) -eq $expected){continue}
    if($null -ne $next[$path]){Write-HuAtomic $path $next[$path]}elseif([IO.File]::Exists($path)){[IO.File]::Delete($path)}
    if((Get-HuHash $path) -ne $expected){throw 'COPY_FAILED'}
   }
  }catch{
   $failure=$_
   try{
    foreach($path in $targets){if((Get-HuHash $path) -ne $hashes[$path]){if($null -ne $old[$path]){Write-HuAtomic $path $old[$path]}elseif([IO.File]::Exists($path)){[IO.File]::Delete($path)}}}
    foreach($path in $targets){if((Get-HuHash $path) -ne $hashes[$path]){throw 'RESTORE_FAILED'}}
    [IO.File]::Delete($pending)
   }catch{throw 'RESTORE_FAILED'}
   throw $failure
  }
  [IO.File]::Delete($pending);$script:HuDetectedComponents=Format-HuComponents $selected;$script:HuDetectedVersion=if($selected.Count){$Package.Version}else{''}
  if($selected.Count -eq 0){Remove-HuRestoredBackups $Folder $backup;$cleanupCompleted=$true;return 'REMOVED'};return 'INSTALLED'
 }finally{
  $lock.Dispose()
  if($cleanupCompleted){
   try{
    [IO.File]::Delete($lockPath)
    if([IO.Directory]::Exists($backup) -and [IO.Directory]::GetFileSystemEntries($backup).Length -eq 0){[IO.Directory]::Delete($backup,$false)}
   }catch{throw 'CLEANUP_FAILED'}
  }
 }
}
function Write-HuReport([string]$State){if(-not [string]::IsNullOrWhiteSpace($ReportPath)){[IO.File]::WriteAllText($ReportPath,"[Result]`r`nState=$State`r`nGameDir=$script:HuResolvedFolder`r`nInstalledComponents=$script:HuDetectedComponents`r`nInstalledVersion=$script:HuDetectedVersion`r`n",[Text.Encoding]::Unicode)}}
if(-not $LibraryOnly){
 try{
  $package=Read-HuPackage $PayloadDir
  if([string]::IsNullOrWhiteSpace($GameDir)){$folder=Find-HuGame}else{$folder=Get-HuFolder $GameDir}
  $script:HuResolvedFolder=$folder
  if($Mode -eq 'Detect'){$result=Get-HuState $folder $package $Components}else{$result=Invoke-HuOperation $folder $package $PayloadDir $Mode $Components}
  Write-HuReport $result;[Console]::WriteLine($result)
  if($result.StartsWith('READY_') -or $result -eq 'INSTALLED' -or $result -eq 'REMOVED' -or $result -eq 'UNCHANGED'){exit 0}else{exit 1}
 }catch{
  $code=$_.Exception.Message
  if(@('NOT_GAME','NOT_STEAM','WRONG_VERSION','GAME_RUNNING','BAD_PACKAGE','BACKUP_CONFLICT','FILE_CONFLICT','STATE_CONFLICT','RECOVERY_NEEDED','NEWER_INSTALLED','VERSION_CONFLICT','OPERATION_BUSY','STATE_CHANGED','COPY_FAILED','RESTORE_FAILED','UNSUPPORTED_LAYOUT','BANNER_UNSUPPORTED','BANNER_LAYOUT','BAD_COMPONENTS','NO_COMPONENTS','CLEANUP_FAILED') -notcontains $code){$code='OPERATION_FAILED'}
  Write-HuReport $code;[Console]::WriteLine($code);exit 1
 }
}

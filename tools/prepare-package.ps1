param([string]$Destination,[string]$InputSdkPath,[switch]$ResolveSdk,[switch]$LibraryOnly)
$ErrorActionPreference='Stop'

function Get-HuPackageHash([string]$Path){
 $sha=[Security.Cryptography.SHA256]::Create();$stream=[IO.File]::OpenRead($Path)
 try{return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
}
function New-HuPackage([string]$Folder,[string]$ProjectRoot){
 $version=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'VERSION')).Trim()
 if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Érvénytelen verzió.'}
 $installer=Join-Path $ProjectRoot 'installer';$payload=Join-Path $Folder 'payload'
 [IO.Directory]::CreateDirectory($payload)|Out-Null
 $files=@(foreach($name in @('content.vfx','content_hun_nextgen2.vfs0','original-content.vfx','Resources.cs')){
  $source=if($name -eq 'Resources.cs'){Join-Path $installer $name}else{Join-Path $installer ('payload\'+$name)}
  Copy-Item -LiteralPath $source -Destination (Join-Path $payload $name)
  [ordered]@{Name=$name;Sha256=(Get-HuPackageHash (Join-Path $payload $name))}
 })
 $manifest=[ordered]@{Product='Harciropi.Metro2033Redux.NextGen.HU';Version=$version;Files=$files}
 $manifestPath=Join-Path $payload 'package.json'
 [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 $hash=(Get-HuPackageHash $manifestPath)
 $backend=Join-Path $Folder 'Kezeles.ps1'
 [IO.File]::WriteAllText($backend,([IO.File]::ReadAllText((Join-Path $installer 'Kezeles.ps1')).Replace('@@MANIFEST_SHA256@@',$hash)),[Text.UTF8Encoding]::new($true))
 return [pscustomobject]@{Version=$version;Stage=$Folder;Backend=$backend;Payload=$payload;ManifestHash=$hash}
}

function Get-HuTestSdk([string]$Path){
 if([string]::IsNullOrWhiteSpace($Path)){
  $game=Find-HuGame;$state=Read-HuState $game
  if($null -ne $state -and -not [string]::IsNullOrWhiteSpace($state.SdkOriginalName)){
   $Path=Join-Path (Join-Path $game $HuBackup) $state.SdkOriginalName
  }else{$Path=Join-Path $game 'pros.sdk.x64.dll'}
 }
 if([Metro2033Hu.BannerFilter]::Inspect([IO.File]::ReadAllBytes($Path)) -ne 'ORIGINAL'){throw 'Az ellenőrzéshez eredeti PROS SDK szükséges.'}
 return [IO.Path]::GetFullPath($Path)
}

function Remove-HuScratch([string]$Folder,[string]$Parent,[string]$Prefix){
 $full=[IO.Path]::GetFullPath($Folder).TrimEnd('\','/');$root=[IO.Path]::GetFullPath($Parent).TrimEnd('\','/')
 if(-not [string]::Equals([IO.Path]::GetDirectoryName($full),$root,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch ('^'+[regex]::Escape($Prefix)+'[a-f0-9]{32}$')){throw 'A takarítás célja nem saját munkamappa.'}
 if(Test-Path -LiteralPath $full){
  foreach($item in @((Get-Item -Force -LiteralPath $full))+@(Get-ChildItem -Force -Recurse -LiteralPath $full)){
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Hivatkozást tartalmazó munkamappa nem takarítható automatikusan.'}
  }
  Remove-Item -LiteralPath $full -Recurse -Force
 }
}

if(-not $LibraryOnly){
 [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
 if([string]::IsNullOrWhiteSpace($Destination)){throw 'Célmappa szükséges.'}
 $package=New-HuPackage $Destination ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
 if($ResolveSdk){
  . $package.Backend -LibraryOnly
  $null=Read-HuPackage $package.Payload
  $package|Add-Member -NotePropertyName SdkPath -NotePropertyValue (Get-HuTestSdk $InputSdkPath)
 }
 $package|ConvertTo-Json
}

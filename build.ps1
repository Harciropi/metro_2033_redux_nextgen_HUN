param([string]$NsisPath,[string]$OutputRoot)
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
. (Join-Path $projectRoot 'tools\prepare-package.ps1') -LibraryOnly
if([string]::IsNullOrWhiteSpace($NsisPath)){
 $compiler=Get-Command makensis.exe -ErrorAction SilentlyContinue
 if($null -ne $compiler){$NsisPath=$compiler.Source}
 else{$NsisPath=Join-Path $projectRoot '.private\compiler\nsis\makensis.exe'}
}
if(-not [IO.File]::Exists($NsisPath)){throw 'NSIS 3 Unicode szükséges. Add meg a fordítót a -NsisPath paraméterrel.'}
$dist=if([string]::IsNullOrWhiteSpace($OutputRoot)){Join-Path $projectRoot 'dist'}else{[IO.Path]::GetFullPath($OutputRoot)}
$stage=Join-Path $dist ('.build-'+[guid]::NewGuid().ToString('N'))
try{
 $package=New-HuPackage $stage $projectRoot;$version=$package.Version
 foreach($file in @('telepito.nsi','wizard-artwork.bmp','metro.ico')){Copy-Item -LiteralPath (Join-Path $projectRoot ('installer\'+$file)) -Destination (Join-Path $stage $file)}
 $nsiPath=Join-Path $stage 'telepito.nsi';$nsi=[IO.File]::ReadAllText($nsiPath)
 $nsi=[regex]::Replace($nsi,'(?m)^VIProductVersion "[^"]+"',('VIProductVersion "'+$version+'.0"'))
 $nsi=[regex]::Replace($nsi,'(?m)^VIAddVersionKey /LANG=1038 "FileVersion" "[^"]+"',('VIAddVersionKey /LANG=1038 "FileVersion" "'+$version+'"'))
 [IO.File]::WriteAllText($nsiPath,$nsi,[Text.UTF8Encoding]::new($true))
 & $NsisPath /V2 $nsiPath
 if($LASTEXITCODE -ne 0){throw 'Az NSIS-fordítás sikertelen.'}
 $release=Join-Path $dist ('v'+$version);[IO.Directory]::CreateDirectory($release)|Out-Null
 $output=Join-Path $release 'Metro2033Redux_NextGen_HU.exe'
 Copy-Item -LiteralPath (Join-Path $stage 'Metro2033Redux_NextGen_HU.exe') -Destination $output
 Write-Output $output
}finally{Remove-HuScratch $stage $dist '.build-'}
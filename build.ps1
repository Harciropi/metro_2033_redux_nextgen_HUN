param([string]$NsisPath)
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
$version=[IO.File]::ReadAllText((Join-Path $projectRoot 'VERSION')).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'A VERSION fájlban major.minor.patch verzió szükséges.'}
if([string]::IsNullOrWhiteSpace($NsisPath)){
 $compiler=Get-Command makensis.exe -ErrorAction SilentlyContinue
 if($null -eq $compiler){throw 'NSIS 3 Unicode szükséges. Add meg a fordítót a -NsisPath paraméterrel.'}
 $NsisPath=$compiler.Source
}
if(-not [IO.File]::Exists($NsisPath)){throw 'A megadott NSIS-fordító nem található.'}
$installer=Join-Path $projectRoot 'installer'
$required=@('telepito.nsi','Kezeles.ps1','wizard-artwork.bmp','metro.ico','payload\content.vfx','payload\content_hun_nextgen2.vfs0','payload\original-content.vfx')
foreach($file in $required){if(-not [IO.File]::Exists((Join-Path $installer $file))){throw "Hiányzó helyi csomagfájl: $file"}}
$dist=Join-Path $projectRoot 'dist'
$stage=Join-Path $dist ('.build-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $stage 'payload') -Force | Out-Null
foreach($file in $required){Copy-Item -LiteralPath (Join-Path $installer $file) -Destination (Join-Path $stage $file)}
$nsiPath=Join-Path $stage 'telepito.nsi'
$nsi=[IO.File]::ReadAllText($nsiPath)
$nsi=[regex]::Replace($nsi,'(?m)^VIProductVersion "[^"]+"',('VIProductVersion "'+$version+'.0"'))
$nsi=[regex]::Replace($nsi,'(?m)^VIAddVersionKey /LANG=1038 "FileVersion" "[^"]+"',('VIAddVersionKey /LANG=1038 "FileVersion" "'+$version+'"'))
[IO.File]::WriteAllText($nsiPath,$nsi,[Text.UTF8Encoding]::new($true))
& $NsisPath /V2 $nsiPath
if($LASTEXITCODE -ne 0){throw 'Az NSIS-fordítás sikertelen.'}
$release=Join-Path $dist ('v'+$version)
New-Item -ItemType Directory -Path $release -Force | Out-Null
$output=Join-Path $release 'Metro2033Redux_NextGen_HU.exe'
Copy-Item -LiteralPath (Join-Path $stage 'Metro2033Redux_NextGen_HU.exe') -Destination $output
Write-Output $output

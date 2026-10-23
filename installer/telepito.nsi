Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
Name "Metro 2033 Redux next-gen magyarítás"
OutFile "Metro2033Redux_NextGen_HU.exe"
RequestExecutionLevel admin
InstallDir "$PROGRAMFILES32\Steam\steamapps\common\Metro 2033 Redux"
InstallDirRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 286690" "InstallLocation"
SetCompressor /SOLID lzma
ShowInstDetails nevershow
VIProductVersion "1.5.0.0"
VIAddVersionKey /LANG=1038 "ProductName" "Metro 2033 Redux next-gen magyarítás"
VIAddVersionKey /LANG=1038 "FileDescription" "Magyarítás telepítése és eltávolítása"
VIAddVersionKey /LANG=1038 "FileVersion" "1.5.0"
VIAddVersionKey /LANG=1038 "LegalCopyright" "Eredeti magyarítás: Lostprophet. Nem hivatalos next-gen kiegészítés."
Var DetectedState
Var Operation
Var WelcomeText
Var ActionTitle
Var ActionSubtitle
Var ActionButton
Var ActionText
Var FinishTitle
Var FinishText
Var RunResult

Icon "metro.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "wizard-artwork.bmp"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Metro 2033 Redux next-gen magyarítás"
!define MUI_WELCOMEPAGE_TEXT "$WelcomeText"
!insertmacro MUI_PAGE_WELCOME
!define MUI_DIRECTORYPAGE_TEXT_TOP "Válaszd ki a Metro 2033 Redux játék mappáját. A telepítő megállapítja, hogy telepítésre, frissítésre vagy eltávolításra van szükség."
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE DirectoryLeave
!insertmacro MUI_PAGE_DIRECTORY
Page custom ReviewShow ReviewLeave
!define MUI_PAGE_CUSTOMFUNCTION_SHOW ProgressShow
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "$FinishTitle"
!define MUI_FINISHPAGE_TEXT "$FinishText"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "Hungarian"

Function RunBackend
 System::Call 'kernel32::SetEnvironmentVariableW(w "METRO_HU_GAME_DIR", w "$INSTDIR")'
 System::Call 'kernel32::SetEnvironmentVariableW(w "METRO_HU_REPORT", w "$PLUGINSDIR\eredmeny.ini")'
 Delete "$PLUGINSDIR\eredmeny.ini"
 nsExec::ExecToStack /TIMEOUT=60000 `"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\Kezeles.ps1" -Mode $Operation`
 Pop $RunResult
 Pop $0
 StrCpy $DetectedState "OPERATION_FAILED"
 ReadINIStr $DetectedState "$PLUGINSDIR\eredmeny.ini" "Result" "State"
 ${If} $DetectedState == ""
  StrCpy $DetectedState "OPERATION_FAILED"
 ${EndIf}
FunctionEnd

Function SelectAction
 ${If} $DetectedState == "READY_REMOVE"
  StrCpy $Operation "Remove"
  StrCpy $ActionTitle "Magyarítás eltávolítása"
  StrCpy $ActionSubtitle "A magyarítás már telepítve van ebben a mappában."
  StrCpy $ActionButton "Eltávolítás"
  StrCpy $ActionText "Az Eltávolítás gombbal visszaállíthatod a játék eredeti angol szövegét.$\r$\n$\r$\nA játékmentéseid és beállításaid megmaradnak. Ha mégsem szeretnéd eltávolítani a magyarítást, válaszd a Mégse gombot."
 ${ElseIf} $DetectedState == "READY_UPGRADE"
  StrCpy $Operation "Install"
  StrCpy $ActionTitle "Magyarítás frissítése"
  StrCpy $ActionSubtitle "A magyarítás egy korábbi változatát találtam."
  StrCpy $ActionButton "Frissítés"
  StrCpy $ActionText "A Frissítés gombbal telepítheted a magyarítás jelenlegi változatát.$\r$\n$\r$\nA játékmentéseid és beállításaid megmaradnak. A játékban az angol szövegnyelvet válaszd."
 ${ElseIf} $DetectedState == "READY_REPAIR"
  StrCpy $Operation "Install"
  StrCpy $ActionTitle "Magyarítás helyreállítása"
  StrCpy $ActionSubtitle "A magyarítás néhány fájlja hiányzik."
  StrCpy $ActionButton "Helyreállítás"
  StrCpy $ActionText "A Helyreállítás gombbal pótolhatod a magyarítás hiányzó fájljait.$\r$\n$\r$\nA játékmentéseid és beállításaid megmaradnak."
 ${ElseIf} $DetectedState == "READY_INSTALL"
  StrCpy $Operation "Install"
  StrCpy $ActionTitle "Magyarítás telepítése"
  StrCpy $ActionSubtitle "A játék készen áll a magyarítás telepítésére."
  StrCpy $ActionButton "Telepítés"
  StrCpy $ActionText "A Telepítés gombbal magyar feliratokat és menüket adhatsz a játékhoz.$\r$\n$\r$\nA játékban az angol szövegnyelvet válaszd. A fegyvernevek eredeti angol alakban szerepelnek.$\r$\n$\r$\nEltávolításhoz később indítsd el újra ezt az EXE-t."
 ${Else}
  StrCpy $Operation ""
 ${EndIf}
FunctionEnd

Function ShowProblem
 ${If} $DetectedState == "NOT_GAME"
  StrCpy $0 "Nem találom a játékot a kiválasztott mappában. Válaszd ki azt a mappát, amelyben a metro.exe található."
 ${ElseIf} $DetectedState == "WRONG_VERSION"
  StrCpy $0 "Ez a magyarítás a Metro 2033 Redux Steam next-gen Windows-kiadásához készült. Válaszd ki ennek a játéknak a mappáját."
 ${ElseIf} $DetectedState == "GAME_RUNNING"
  StrCpy $0 "A játék fut, vagy a futási állapota nem ellenőrizhető. Zárd be a játékot, majd próbáld újra."
 ${ElseIf} $DetectedState == "FILE_CONFLICT"
  StrCpy $0 "Másik vagy módosított magyarításfájl található a mappában. A telepítő nem írja felül."
 ${ElseIf} $DetectedState == "BACKUP_CONFLICT"
  StrCpy $0 "Az eredeti játékfájl korábbi biztonsági másolata megváltozott. A telepítő nem írja felül."
 ${ElseIf} $DetectedState == "BAD_PACKAGE"
  StrCpy $0 "A telepítő fájljainak ellenőrzése sikertelen. Töltsd le újra a telepítőt, és próbáld meg még egyszer."
 ${ElseIf} $DetectedState == "STATE_CHANGED"
  StrCpy $0 "A játék fájljai időközben megváltoztak. Indítsd újra a telepítőt."
 ${ElseIf} $DetectedState == "RESTORE_FAILED"
  StrCpy $0 "A művelet és a visszaállítás sem sikerült teljesen. Zárd be a játékot, majd használd a Steam játékfájl-ellenőrzését az eredeti állapot visszaállításához."
 ${Else}
  StrCpy $0 "A művelet nem sikerült. Ellenőrizd, hogy a játék zárva van-e, a játékmappa írható-e, és van-e elegendő szabad hely."
 ${EndIf}
 MessageBox MB_OK|MB_ICONSTOP "$0" /SD IDOK
FunctionEnd

Function .onInit
 InitPluginsDir
 SetOutPath "$PLUGINSDIR"
 File "Kezeles.ps1"
 SetOutPath "$PLUGINSDIR\payload"
 File "payload\content.vfx"
 File "payload\content_hun_nextgen2.vfs0"
 File "payload\original-content.vfx"
 StrCpy $Operation "Detect"
 Call RunBackend
 Call SelectAction
 StrCpy $WelcomeText "Magyar feliratok és menük a Metro 2033 Redux Steam next-gen kiadásához.$\r$\n$\r$\nTelepítéshez és eltávolításhoz is ezt az EXE-t használd. A játékot előtte zárd be.$\r$\n$\r$\nEredeti magyarítás: Lostprophet.$\r$\n$\r$\nAz eredeti magyarítás óta megjelent új szövegek fordítását és az új telepítőt Harciropi készítette.$\r$\n$\r$\nNem hivatalos, közösségi magyarítás."
 ${If} $DetectedState == "READY_REMOVE"
  StrCpy $WelcomeText "A magyarítás már telepítve van a felismert játékmappában. Ezzel az EXE-vel most eltávolíthatod.$\r$\n$\r$\nA játékmentéseid és beállításaid megmaradnak.$\r$\n$\r$\nEredeti magyarítás: Lostprophet.$\r$\n$\r$\nAz eredeti magyarítás óta megjelent új szövegek fordítását és az új telepítőt Harciropi készítette.$\r$\n$\r$\nNem hivatalos, közösségi magyarítás."
 ${EndIf}
FunctionEnd

Function DirectoryLeave
 StrCpy $Operation "Detect"
 Call RunBackend
 Call SelectAction
 ${If} $Operation == ""
  Call ShowProblem
  Abort
 ${EndIf}
FunctionEnd

Function ReviewShow
 StrCpy $Operation "Detect"
 Call RunBackend
 Call SelectAction
 ${If} $Operation == ""
  Call ShowProblem
  Abort
 ${EndIf}
 !insertmacro MUI_HEADER_TEXT "$ActionTitle" "$ActionSubtitle"
 nsDialogs::Create 1018
 Pop $0
 ${If} $0 == error
  Abort
 ${EndIf}
 ${NSD_CreateLabel} 0 4u 100% 16u "Kiválasztott játékmappa:"
 Pop $0
 ${NSD_CreateLabel} 0 22u 100% 28u "$INSTDIR"
 Pop $0
 ${NSD_CreateLabel} 0 56u 100% 96u "$ActionText"
 Pop $0
 GetDlgItem $0 $HWNDPARENT 1
 SendMessage $0 ${WM_SETTEXT} 0 "STR:$ActionButton"
 nsDialogs::Show
FunctionEnd

Function ReviewLeave
 ; A végső művelet az állapotot újra ellenőrzi, mielőtt bármit módosítana.
FunctionEnd

Function ProgressShow
 !insertmacro MUI_HEADER_TEXT "$ActionTitle" "Kérlek, várj, amíg a művelet befejeződik."
FunctionEnd

Section "Magyarítás"
 ${If} $Operation == ""
 ${OrIf} $Operation == "Detect"
  StrCpy $Operation "Detect"
  Call RunBackend
  Call SelectAction
 ${EndIf}
 ${If} $Operation == ""
  Call ShowProblem
  SetErrorLevel 2
  Abort
 ${EndIf}
 Call RunBackend
 ${If} $DetectedState == "INSTALLED"
  StrCpy $FinishTitle "A magyarítás telepítése elkészült"
  StrCpy $FinishText "Indítsd el a játékot, és a szövegnyelvnél válaszd az angolt.$\r$\n$\r$\nA menük és feliratok magyarul jelennek meg. A fegyvernevek angolul maradnak.$\r$\n$\r$\nHa később el szeretnéd távolítani a magyarítást, indítsd el újra ezt az EXE-t."
 ${ElseIf} $DetectedState == "REMOVED"
  StrCpy $FinishTitle "A magyarítás eltávolítása elkészült"
  StrCpy $FinishText "Visszaállt a játék eredeti angol szövege.$\r$\n$\r$\nA játékmentéseid és beállításaid megmaradtak.$\r$\n$\r$\nA magyarítást később ugyanezzel az EXE-vel ismét telepítheted."
 ${Else}
  Call ShowProblem
  SetErrorLevel 2
  Abort
 ${EndIf}
SectionEnd
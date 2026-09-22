; NOVA for Windows installer (NSIS 3): nova.exe on the PATH, WIC codec registered (Explorer thumbnails,
; Photos), uninstaller in Settings > Apps. Built by win/dist.sh from dist/nova-windows/.
; Per-user (no admin) or per-machine (admin) install, picked on a wizard page: MultiUser.nsh
; handles the privilege check, the registry hive (ShCtx) and $InstDir for both modes.
Unicode true
!include x64.nsh
!include WinMessages.nsh
!include StrFunc.nsh
${UnStrRep}

!define UNINST "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOVA"
!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_KEY "${UNINST}"
!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_VALUENAME "InstallMode"
!define MULTIUSER_INSTALLMODE_INSTDIR "NOVA"
!define MULTIUSER_EXECUTIONLEVEL Highest
!define MULTIUSER_MUI

!include LogicLib.nsh
!include MultiUser.nsh
!include MUI2.nsh

Name "NOVA"
OutFile "..\dist\nova-setup.exe"
SetCompressor /SOLID lzma
Icon "nova.ico"
UninstallIcon "nova.ico"
ManifestDPIAware true

!define ENV_ALLUSERS "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
!define ENV_CURRENTUSER "Environment"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MULTIUSER_PAGE_INSTALLMODE
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "NOVA needs 64-bit Windows."
    Abort
  ${EndIf}
  !insertmacro MULTIUSER_INIT
  SetRegView 64
FunctionEnd

Function un.onInit
  !insertmacro MULTIUSER_UNINIT
  SetRegView 64
FunctionEnd

; Active Setup runs a command once per user, in that user's own session, the next time they log
; on. It is the only way a per-machine install can reach a real user's PowerShell profile: a
; process elevated to install writes the profile of the account that elevated, and an MSI custom
; action writes SYSTEM's.
!define ACTIVESETUP "SOFTWARE\Microsoft\Active Setup\Installed Components\{B7E2A93C-5F14-4A88-9C3D-61D0A7F2E845}"

Section "NOVA" SecCore
  SectionIn RO
  SetOutPath "$InstDir"
  File "..\dist\nova-windows\nova.exe"
  File "..\dist\nova-windows\nova-profile.ps1"
  ; Every DLL win/dist.sh staged: the codec, zlib/libwebp, and LibRaw with its own dependencies.
  ; A glob so that adding one to dist.sh does not silently leave it out of the installer.
  File "..\dist\nova-windows\*.dll"
  File "..\dist\nova-windows\nova-completion.ps1"
  File "..\dist\nova-windows\LICENSE-*.txt"
  File "..\dist\nova-windows\README.txt"
  SetOutPath "$InstDir\samples"
  File "..\dist\nova-windows\*.nova"
  WriteUninstaller "$InstDir\uninstall.exe"

  ; the installer is 32-bit: run the 64-bit regsvr32 for the 64-bit codec
  ${DisableX64FSRedirection}
  ExecWait '"$SYSDIR\regsvr32.exe" /s "$InstDir\nova_wic.dll"' $0
  ${EnableX64FSRedirection}
  StrCmp $0 0 +2
    MessageBox MB_OK|MB_ICONEXCLAMATION "The viewer codec could not be registered (regsvr32 error $0)."

  ; nova.exe on the PATH (new terminals): HKLM for an all-users install, HKCU for the current user only
  ; NSIS strings stop at ${NSIS_MAX_STRLEN} characters: a longer PATH would come back cut, so leave it alone
  ${if} $MultiUser.InstallMode == "AllUsers"
    ReadRegStr $1 HKLM "${ENV_ALLUSERS}" "Path"
  ${else}
    ReadRegStr $1 HKCU "${ENV_CURRENTUSER}" "Path"
  ${endif}
  StrLen $3 "$1;$InstDir"
  IntCmp $3 ${NSIS_MAX_STRLEN} pathlong 0 pathlong
  Push $1
  Push ";$InstDir"
  Call StrContains
  Pop $2
  StrCmp $2 "" 0 pathdone
    ${if} $MultiUser.InstallMode == "AllUsers"
      WriteRegExpandStr HKLM "${ENV_ALLUSERS}" "Path" "$1;$InstDir"
    ${else}
      WriteRegExpandStr HKCU "${ENV_CURRENTUSER}" "Path" "$1;$InstDir"
    ${endif}
    Goto pathdone
  pathlong:
    MessageBox MB_OK "Your PATH is too long to edit safely: add $InstDir to it yourself to run nova from a terminal."
  pathdone:
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=2000

  WriteRegStr ShCtx "${UNINST}" "DisplayName" "NOVA image format"
  WriteRegStr ShCtx "${UNINST}" "DisplayVersion" "2.0"
  WriteRegStr ShCtx "${UNINST}" "Publisher" "Thibault SAVENKOFF"
  WriteRegStr ShCtx "${UNINST}" "InstallLocation" "$InstDir"
  WriteRegStr ShCtx "${UNINST}" "DisplayIcon" "$InstDir\nova.exe,0"
  WriteRegStr ShCtx "${UNINST}" "UninstallString" '"$InstDir\uninstall.exe"'
  WriteRegDWORD ShCtx "${UNINST}" "NoModify" 1
  WriteRegDWORD ShCtx "${UNINST}" "NoRepair" 1
  WriteRegStr ShCtx "${UNINST}" "InstallMode" "$MultiUser.InstallMode"
SectionEnd

; PowerShell has no auto-load directory for argument completers, so the completion only works once
; a line loads it from the user's profile. PowerShell edits its own file (nova-profile.ps1) rather
; than NSIS guessing its encoding; the script is idempotent, so running it twice changes nothing.
Section -Completion
  ; Now, for whoever is installing: UAC elevates the same account on a personal machine, so the
  ; profile written is the right one. Active Setup then covers the case that breaks -- another
  ; account's credentials at the UAC prompt -- and every other user of a per-machine install.
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$InstDir\nova-profile.ps1" -Script "$InstDir\nova-completion.ps1"'
  ${if} $MultiUser.InstallMode == "AllUsers"
    WriteRegStr HKLM "${ACTIVESETUP}" "" "NOVA tab completion"
    WriteRegStr HKLM "${ACTIVESETUP}" "Version" "1"
    WriteRegStr HKLM "${ACTIVESETUP}" "StubPath" '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$InstDir\nova-profile.ps1" -Script "$InstDir\nova-completion.ps1"'
  ${endif}
SectionEnd

; Pushes "" if the needle (top) is not in the haystack (below it), else the needle.
Function StrContains
  Exch $R0   ; needle
  Exch
  Exch $R1   ; haystack
  Push $R2
  Push $R3
  Push $R4
  StrLen $R2 $R0
  StrCpy $R4 0
  loop:
    StrCpy $R3 $R1 $R2 $R4
    StrCmp $R3 $R0 found
    StrCmp $R3 "" notfound
    IntOp $R4 $R4 + 1
    Goto loop
  notfound:
    StrCpy $R0 ""
  found:
  Pop $R4
  Pop $R3
  Pop $R2
  Pop $R1
  Exch $R0
FunctionEnd

Section "Uninstall"
  ${DisableX64FSRedirection}
  ExecWait '"$SYSDIR\regsvr32.exe" /s /u "$InstDir\nova_wic.dll"'
  ${EnableX64FSRedirection}
  ${if} $MultiUser.InstallMode == "AllUsers"
    ReadRegStr $1 HKLM "${ENV_ALLUSERS}" "Path"
  ${else}
    ReadRegStr $1 HKCU "${ENV_CURRENTUSER}" "Path"
  ${endif}
  StrLen $3 $1
  IntCmp $3 ${NSIS_MAX_STRLEN} unpathdone 0 unpathdone
  ${UnStrRep} $1 $1 ";$InstDir" ""
  ${if} $MultiUser.InstallMode == "AllUsers"
    WriteRegExpandStr HKLM "${ENV_ALLUSERS}" "Path" $1
  ${else}
    WriteRegExpandStr HKCU "${ENV_CURRENTUSER}" "Path" $1
  ${endif}
  unpathdone:
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=2000
  DeleteRegKey ShCtx "${UNINST}"
  DeleteRegKey HKLM "${ACTIVESETUP}"
  ; Only this user's profile: Active Setup has no undo, so a line it added for another account
  ; stays until that user runs nova-profile.ps1 -Remove. It loads nothing once the file is gone.
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$InstDir\nova-profile.ps1" -Remove'
  RMDir /r "$InstDir\samples"
  Delete "$InstDir\*.exe"
  Delete /REBOOTOK "$InstDir\*.dll"   ; Explorer may still hold the codec
  Delete "$InstDir\LICENSE-*.txt"
  Delete "$InstDir\README.txt"
  Delete "$InstDir\nova-completion.ps1"
  Delete "$InstDir\nova-profile.ps1"
  RMDir "$InstDir"
SectionEnd

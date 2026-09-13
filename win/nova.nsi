; NOVA for Windows installer (NSIS 3): nova.exe on the PATH, WIC codec registered (Explorer thumbnails,
; Photos), uninstaller in Settings > Apps. Built by win/dist.sh from dist/nova-windows/.
Unicode true
!include x64.nsh
!include WinMessages.nsh
!include StrFunc.nsh
${UnStrRep}

Name "NOVA"
OutFile "..\dist\nova-setup.exe"
InstallDir "$PROGRAMFILES64\NOVA"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!define ENV "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
!define UNINST "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOVA"

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "NOVA needs 64-bit Windows."
    Abort
  ${EndIf}
  SetRegView 64
FunctionEnd

Section
  SetOutPath "$INSTDIR"
  File "..\dist\nova-windows\nova.exe"
  File "..\dist\nova-windows\nova_wic.dll"
  File "..\dist\nova-windows\zlib1.dll"
  File "..\dist\nova-windows\libwebp-7.dll"
  File "..\dist\nova-windows\libsharpyuv-0.dll"
  File "..\dist\nova-windows\LICENSE-*.txt"
  SetOutPath "$INSTDIR\samples"
  File "..\dist\nova-windows\*.nova"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; the installer is 32-bit: run the 64-bit regsvr32 for the 64-bit codec
  ${DisableX64FSRedirection}
  ExecWait '"$SYSDIR\regsvr32.exe" /s "$INSTDIR\nova_wic.dll"' $0
  ${EnableX64FSRedirection}
  StrCmp $0 0 +2
    MessageBox MB_OK|MB_ICONEXCLAMATION "The viewer codec could not be registered (regsvr32 error $0)."

  ; nova.exe on the system PATH (new terminals)
  ; NSIS strings stop at ${NSIS_MAX_STRLEN} characters: a longer PATH would come back cut, so leave it alone
  ReadRegStr $1 HKLM "${ENV}" "Path"
  StrLen $3 "$1;$INSTDIR"
  IntCmp $3 ${NSIS_MAX_STRLEN} pathlong 0 pathlong
  Push $1
  Push ";$INSTDIR"
  Call StrContains
  Pop $2
  StrCmp $2 "" 0 pathdone
    WriteRegExpandStr HKLM "${ENV}" "Path" "$1;$INSTDIR"
    Goto pathdone
  pathlong:
    MessageBox MB_OK "Your PATH is too long to edit safely: add $INSTDIR to it yourself to run nova from a terminal."
  pathdone:
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=2000

  WriteRegStr HKLM "${UNINST}" "DisplayName" "NOVA image format"
  WriteRegStr HKLM "${UNINST}" "DisplayVersion" "2.0"
  WriteRegStr HKLM "${UNINST}" "Publisher" "Thibault Savenkoff"
  WriteRegStr HKLM "${UNINST}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "${UNINST}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST}" "NoRepair" 1
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

Function un.onInit
  SetRegView 64
FunctionEnd

Section "Uninstall"
  ${DisableX64FSRedirection}
  ExecWait '"$SYSDIR\regsvr32.exe" /s /u "$INSTDIR\nova_wic.dll"'
  ${EnableX64FSRedirection}
  ReadRegStr $1 HKLM "${ENV}" "Path"
  StrLen $3 $1
  IntCmp $3 ${NSIS_MAX_STRLEN} unpathdone 0 unpathdone
  ${UnStrRep} $1 $1 ";$INSTDIR" ""
  WriteRegExpandStr HKLM "${ENV}" "Path" $1
  unpathdone:
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=2000
  DeleteRegKey HKLM "${UNINST}"
  RMDir /r "$INSTDIR\samples"
  Delete "$INSTDIR\*.exe"
  Delete /REBOOTOK "$INSTDIR\*.dll"   ; Explorer may still hold the codec
  Delete "$INSTDIR\LICENSE-*.txt"
  RMDir "$INSTDIR"
SectionEnd

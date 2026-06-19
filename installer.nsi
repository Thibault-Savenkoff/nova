; NOVA Viewer — NSIS installer script
; No admin required; elevates automatically if available.

!define APP_NAME   "NOVA Viewer"
!define EXE_NAME   "NOVAViewer.exe"
!define UNREG_KEY  "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOVAViewer"

Name "${APP_NAME}"
OutFile "NOVAViewer-setup.exe"
; Default dir set dynamically in .onInit based on admin status
InstallDir ""
RequestExecutionLevel highest   ; UAC prompt if admin available, else run as user
SetCompressor /SOLID lzma

; Modern UI
!include "MUI2.nsh"
!include "LogicLib.nsh"
!define MUI_ICON "assets\nova_viewer.ico"
!define MUI_UNICON "assets\nova_viewer.ico"
!define MUI_WELCOMEPAGE_TITLE "Install ${APP_NAME}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE_NAME}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch NOVA Viewer"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "French"
!insertmacro MUI_LANGUAGE "English"

VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName"     "${APP_NAME}"
VIAddVersionKey "CompanyName"     "Thibault Savenkoff"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "FileVersion"     "1.0.0"
VIAddVersionKey "LegalCopyright"  "© 2026 Thibault Savenkoff"

; ── detect admin at startup → set install dir + reg hive ──────────────────────
Var IsAdmin

Function .onInit
  UserInfo::GetAccountType
  Pop $IsAdmin   ; "Admin" | "Power" | "User" | "Guest"
  ${If} $IsAdmin == "Admin"
    StrCpy $INSTDIR "$PROGRAMFILES64\NOVAViewer"
  ${Else}
    StrCpy $INSTDIR "$LOCALAPPDATA\NOVAViewer"
  ${EndIf}
FunctionEnd

; ── install ───────────────────────────────────────────────────────────────────
Section "Install"
  SetOutPath "$INSTDIR"
  File "dist\${EXE_NAME}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Uninstall entry — HKLM for admins, HKCU for users
  ${If} $IsAdmin == "Admin"
    WriteRegStr   HKLM "${UNREG_KEY}" "DisplayName"     "${APP_NAME}"
    WriteRegStr   HKLM "${UNREG_KEY}" "UninstallString"  "$INSTDIR\Uninstall.exe"
    WriteRegStr   HKLM "${UNREG_KEY}" "InstallLocation"  "$INSTDIR"
    WriteRegStr   HKLM "${UNREG_KEY}" "DisplayIcon"      "$INSTDIR\${EXE_NAME},0"
    WriteRegStr   HKLM "${UNREG_KEY}" "Publisher"        "Thibault Savenkoff"
    WriteRegDWORD HKLM "${UNREG_KEY}" "NoModify"         1
    WriteRegDWORD HKLM "${UNREG_KEY}" "NoRepair"         1

    WriteRegStr HKLM "Software\Classes\.nova"                        ""  "NOVAImage"
    WriteRegStr HKLM "Software\Classes\NOVAImage"                    ""  "NOVA Image"
    WriteRegStr HKLM "Software\Classes\NOVAImage\DefaultIcon"        ""  "$INSTDIR\${EXE_NAME},0"
    WriteRegStr HKLM "Software\Classes\NOVAImage\shell\open\command" ""  '"$INSTDIR\${EXE_NAME}" "%1"'
  ${Else}
    WriteRegStr   HKCU "${UNREG_KEY}" "DisplayName"     "${APP_NAME}"
    WriteRegStr   HKCU "${UNREG_KEY}" "UninstallString"  "$INSTDIR\Uninstall.exe"
    WriteRegStr   HKCU "${UNREG_KEY}" "InstallLocation"  "$INSTDIR"
    WriteRegStr   HKCU "${UNREG_KEY}" "DisplayIcon"      "$INSTDIR\${EXE_NAME},0"
    WriteRegStr   HKCU "${UNREG_KEY}" "Publisher"        "Thibault Savenkoff"
    WriteRegDWORD HKCU "${UNREG_KEY}" "NoModify"         1
    WriteRegDWORD HKCU "${UNREG_KEY}" "NoRepair"         1

    WriteRegStr HKCU "Software\Classes\.nova"                        ""  "NOVAImage"
    WriteRegStr HKCU "Software\Classes\NOVAImage"                    ""  "NOVA Image"
    WriteRegStr HKCU "Software\Classes\NOVAImage\DefaultIcon"        ""  "$INSTDIR\${EXE_NAME},0"
    WriteRegStr HKCU "Software\Classes\NOVAImage\shell\open\command" ""  '"$INSTDIR\${EXE_NAME}" "%1"'
  ${EndIf}

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'

  ; Start Menu + Desktop shortcuts
  CreateDirectory "$SMPROGRAMS\NOVAViewer"
  CreateShortcut  "$SMPROGRAMS\NOVAViewer\${APP_NAME}.lnk" "$INSTDIR\${EXE_NAME}"
  CreateShortcut  "$SMPROGRAMS\NOVAViewer\Uninstall.lnk"   "$INSTDIR\Uninstall.exe"
  CreateShortcut  "$DESKTOP\${APP_NAME}.lnk"               "$INSTDIR\${EXE_NAME}"
SectionEnd

; ── uninstall ─────────────────────────────────────────────────────────────────
Section "Uninstall"
  Delete "$INSTDIR\${EXE_NAME}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir  "$INSTDIR"

  Delete "$SMPROGRAMS\NOVAViewer\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\NOVAViewer\Uninstall.lnk"
  RMDir  "$SMPROGRAMS\NOVAViewer"
  Delete "$DESKTOP\${APP_NAME}.lnk"

  ; Try both HKLM and HKCU — only one will have entries
  DeleteRegKey HKLM "${UNREG_KEY}"
  DeleteRegKey HKCU "${UNREG_KEY}"
  DeleteRegKey HKLM "Software\Classes\.nova"
  DeleteRegKey HKLM "Software\Classes\NOVAImage"
  DeleteRegKey HKCU "Software\Classes\.nova"
  DeleteRegKey HKCU "Software\Classes\NOVAImage"

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

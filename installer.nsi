; NOVA Viewer — NSIS installer
; Shows an install-type page: "Just me" (AppData, no UAC) or "All users" (Program Files, UAC).

!define APP_NAME   "NOVA Viewer"
!define EXE_NAME   "NOVAViewer.exe"
!define UNREG_KEY  "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOVAViewer"

Name "${APP_NAME}"
OutFile "NOVAViewer-setup.exe"
InstallDir "$LOCALAPPDATA\NOVAViewer"   ; overridden in .onInit if /ALLUSERS
RequestExecutionLevel user              ; start without UAC; elevate only if user picks "All users"
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!include "FileFunc.nsh"

!define MUI_ICON   "assets\nova_viewer.ico"
!define MUI_UNICON "assets\nova_viewer.ico"
!define MUI_WELCOMEPAGE_TITLE "Install ${APP_NAME}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE_NAME}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch NOVA Viewer"

; Custom install-type page comes first
Page custom InstallTypePage InstallTypeLeave
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

; ── variables ────────────────────────────────────────────────────────────────
Var InstallMode   ; "user" | "admin"
Var RadioUser
Var RadioAdmin

; ── init: detect if re-launched with /ALLUSERS (already elevated) ─────────────
Function .onInit
  StrCpy $InstallMode "user"

  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/ALLUSERS" $R1
  ${IfNot} ${Errors}
    StrCpy $InstallMode "admin"
    StrCpy $INSTDIR "$PROGRAMFILES64\NOVAViewer"
    ; Skip the type page — already chose admin
    Call SkipTypePage
  ${EndIf}
FunctionEnd

Function SkipTypePage
  ; Advance past our custom page automatically
  ; (called only when relaunched as admin)
FunctionEnd

; ── custom install-type page ─────────────────────────────────────────────────
Function InstallTypePage
  ; Don't show if already elevated via /ALLUSERS
  ${If} $InstallMode == "admin"
    Abort
  ${EndIf}

  nsDialogs::Create 1018
  Pop $0

  ${NSD_CreateLabel} 0 0 100% 24u "Choose who this application is installed for:"
  Pop $0

  ${NSD_CreateRadioButton} 10u 30u 100% 14u "Just me — no administrator rights required"
  Pop $RadioUser
  ${NSD_Check} $RadioUser   ; default

  ${NSD_CreateLabel} 28u 46u 100% 20u "Installs to: $LOCALAPPDATA\NOVAViewer"
  Pop $0

  ${NSD_CreateRadioButton} 10u 72u 100% 14u "All users — requires administrator rights (UAC prompt)"
  Pop $RadioAdmin

  ${NSD_CreateLabel} 28u 88u 100% 20u "Installs to: $PROGRAMFILES64\NOVAViewer"
  Pop $0

  nsDialogs::Show
FunctionEnd

Function InstallTypeLeave
  ${NSD_GetState} $RadioAdmin $R0
  ${If} $R0 == ${BST_CHECKED}
    ; User picked "All users" — re-launch self elevated with /ALLUSERS flag
    ExecShell "runas" "$EXEPATH" "/ALLUSERS" SW_SHOW
    Quit
  ${Else}
    StrCpy $InstallMode "user"
    StrCpy $INSTDIR "$LOCALAPPDATA\NOVAViewer"
  ${EndIf}
FunctionEnd

; ── install ───────────────────────────────────────────────────────────────────
Section "Install"
  SetOutPath "$INSTDIR"
  File "dist\${EXE_NAME}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ${If} $InstallMode == "admin"
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

  CreateDirectory "$SMPROGRAMS\NOVAViewer"
  CreateShortcut  "$SMPROGRAMS\NOVAViewer\${APP_NAME}.lnk" "$INSTDIR\${EXE_NAME}" "" "$INSTDIR\${EXE_NAME}" 0
  CreateShortcut  "$SMPROGRAMS\NOVAViewer\Uninstall.lnk"   "$INSTDIR\Uninstall.exe"
  CreateShortcut  "$DESKTOP\${APP_NAME}.lnk"               "$INSTDIR\${EXE_NAME}" "" "$INSTDIR\${EXE_NAME}" 0
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

  DeleteRegKey HKLM "${UNREG_KEY}"
  DeleteRegKey HKCU "${UNREG_KEY}"
  DeleteRegKey HKLM "Software\Classes\.nova"
  DeleteRegKey HKLM "Software\Classes\NOVAImage"
  DeleteRegKey HKCU "Software\Classes\.nova"
  DeleteRegKey HKCU "Software\Classes\NOVAImage"

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

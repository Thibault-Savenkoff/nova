; NOVA Viewer — NSIS installer script
; Installs per-user to AppData\Local (no admin/UAC required).

!define APP_NAME   "NOVA Viewer"
!define EXE_NAME   "NOVAViewer.exe"
!define UNREG_KEY  "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOVAViewer"

Name "${APP_NAME}"
OutFile "NOVAViewer-setup.exe"
InstallDir "$LOCALAPPDATA\NOVAViewer"
InstallDirRegKey HKCU "Software\NOVAViewer" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma

; Modern UI
!include "MUI2.nsh"
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

; ── install ───────────────────────────────────────────────────────────────────
Section "Install"
  SetOutPath "$INSTDIR"
  File "dist\${EXE_NAME}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Per-user uninstall entry (no admin needed)
  WriteRegStr   HKCU "${UNREG_KEY}" "DisplayName"     "${APP_NAME}"
  WriteRegStr   HKCU "${UNREG_KEY}" "UninstallString"  "$INSTDIR\Uninstall.exe"
  WriteRegStr   HKCU "${UNREG_KEY}" "InstallLocation"  "$INSTDIR"
  WriteRegStr   HKCU "${UNREG_KEY}" "DisplayIcon"      "$INSTDIR\${EXE_NAME},0"
  WriteRegStr   HKCU "${UNREG_KEY}" "Publisher"        "Thibault Savenkoff"
  WriteRegDWORD HKCU "${UNREG_KEY}" "NoModify"         1
  WriteRegDWORD HKCU "${UNREG_KEY}" "NoRepair"         1

  ; Per-user .nova file association
  WriteRegStr HKCU "Software\Classes\.nova"                        ""  "NOVAImage"
  WriteRegStr HKCU "Software\Classes\NOVAImage"                    ""  "NOVA Image"
  WriteRegStr HKCU "Software\Classes\NOVAImage\DefaultIcon"        ""  "$INSTDIR\${EXE_NAME},0"
  WriteRegStr HKCU "Software\Classes\NOVAImage\shell\open\command" ""  '"$INSTDIR\${EXE_NAME}" "%1"'

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'

  ; Start Menu + Desktop shortcuts (with explicit icon for HD display)
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

  DeleteRegKey HKCU "${UNREG_KEY}"
  DeleteRegKey HKCU "Software\Classes\.nova"
  DeleteRegKey HKCU "Software\Classes\NOVAImage"

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

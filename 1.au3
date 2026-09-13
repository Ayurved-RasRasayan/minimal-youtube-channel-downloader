#include <AutoItConstants.au3>
#include <MsgBoxConstants.au3>

Local $sWorkDir = "C:\Program Files (x86)\multi-channel-ytl-main"
Local $sBatFile = $sWorkDir & "\1.bat"

If Not FileExists($sBatFile) Then
    MsgBox($MB_ICONERROR, "Aborted", "1.bat not found at:" & @CRLF & $sBatFile)
    Exit
EndIf

; /k keeps the console open after 1.bat finishes.
; Quoting: cmd /k ""C:\...\1.bat""
Local $sArgs = ' /k ""' & $sBatFile & '""'

Local $iResult = ShellExecute(@ComSpec, $sArgs, $sWorkDir, "runas")

If $iResult <= 32 Then
    MsgBox($MB_ICONERROR, "Error", "Failed to launch. Code: " & $iResult)
EndIf
::NAME: StickyCopy.bat
::PURPOSE: Copy sticky notes to proper locations after USMT and user login
::VERSION: 1.0, 2019-2-15 11:18
::Functional: yes

::@echo off
SETLOCAL ENABLEDELAYEDEXPANSION
TITLE StickyCopy
CLS

:Start
If Exist "C:\usmt\%username%\StickyNotes\7" (robocopy "C:\usmt\%username%\StickyNotes\7" "%userprofile%\AppData\Local\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\localstate\Legacy" ThresholdNotes.snt)
If Exist "C:\usmt\%username%\StickyNotes\10" (robocopy "c:\usmt\%username%\StickyNotes\10" "%userprofile%\AppData\Local\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\localstate" /e)

:EOF
Timeout 10
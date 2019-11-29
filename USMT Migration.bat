::NAME: USMT Migration Omaha
::PURPOSE: Remotely backup a user profile using USMT and/or restore it to a remote PC. Also works on local PC. Does not require launching as Admin but does require Admin priveleges on the target PC.
::VERSION: 1.1, 2019-2-22
::Functional: YES
	:: https://docs.microsoft.com/en-us/windows/deployment/usmt/usmt-technical-reference
@echo off
SETLOCAL ENABLEDELAYEDEXPANSION
TITLE USMT Profile Migration
CLS

:START
:: User State Migration Tool (USMT) is a scriptable, command line based set of tools for exporting user and computer data from old systems and importing it to a new PC or OS.
:: USMT was desigend as an extension and continuance of the Windows 7 Easy Transfer Tool which has been depracated in Windows 10 and can't be ported over en masse. 
:: This script is designed to automate exporting a single, specific user profile from a remote PC using PSEXEC and the ScanState command, 
::   store the migration file locally, copy it to a share, then run run again to import a migraton file to a remote PC.
:: PSEXEC allows remotely running these commands but can target the local PC and local users. The process is the same.
:: In summary: 
::	1. Run script, specify target PC and user for export
::	2. Run script, specify target PC and user for import
::  3. Configure new PC per the doc
:: The script handles copying the migration files to or from the share and uses the specified username for naming the migration directory. This directory is like %username%\USMT\USMT.MIG.
:: The share location may also need to be scrubbed of old migration directories periodically or be saved to a share based in Chantilly (slower ROBOCOPY speeds) to bypass disk space constraints.
:: This should be run remotely and operate via share directly.
:: This is automated by the script but consumes network bandwidth, disk space across 3 systems (old, new PC, and share), and takes more time to complete.

:VARIABLES
:: This section sets up initial, script wide variables for the USMNT directory on the share (USMTDir), migration file store path (StoreDir).
:: Later sections establish variables for target username and target computer name.
:: For ESC and creation of this script we used an IT PC that stores installs and other software. It has a secondary drive that can store many one off migrations and can be set to delette older folders if needed.
:: Variable summary:
:: USMTDir - Path to USMT tools Scanstate.exe and Loadstate.exe
:: E/IArch - The architecture of the target PC OS.
:: StoreDir - Path to share directory for migration file storage
:: ChromeDir - Path to Chrome Bookmarks. Import is automated.
:: StickyDir - Path to Windows 10 stick notes. Import is automated for Windows 10. For Windows 7, see instructions for import.
:: ECOMPNAME - Target PC name for exporting/scanstate command
:: EUSERNA - Target username for exporting/scanstate command
:: ICOMPNAME - Target PC name for importing/loadstate command
:: IUSERNA - Target user for importing/loadstate command

SET USMTDir=\\Eugene-1\Shared\ITStuff\USMT
SET StoreDir=\\Omaha51\wstech\data2\USMT\Migration
:: Appdata location for Chrome bookmarks
SET ChromeDir=AppData\Local\Google\Chrome\User Data\Default
:: Appdata location for Windows 10 sticky notes
SET StickyDir=AppData\Local\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe

:: This script does use PSEXEC which needs to be copied to the host PC %windir%\system32 if missing
IF NOT EXIST c:\windows\system32\psexec.exe ROBOCOPY "%USMTDir%" "%windir%\system32" psexec.exe

:SCANORLOAD
:: This section determines wether to run the scanstate or loadstate tool.
:: The script redirects here when export or import completes. This menu can be updated for clarity. I used 1 and 2 as the input options to keep it simple and faster to run.
:: This is a standard block used in other scripts but may have alternative methods based on preference. It is tested working OK.
ECHO.
ECHO RUN SCANSTATE (1) OR LOADSTATE (2)? 
ECHO.
SET OPTION=0
SET /P OPTION="ENTER CHOICE 1 OR 2:"
IF %OPTION% equ 0 GOTO SCANORLOAD
IF %OPTION% equ 1 GOTO EXPORTSCANSTATESTART
IF %OPTION% equ 2 GOTO IMPORTLOADSTATESTART
GOTO SCANORLOAD

:EXPORTSCANSTATESTART
:: Although this tells the user it will run remote, inputting the local PC name will work too. Local is not the recommended process.
ECHO.
ECHO THIS TOOL ALLOWS YOU TO RUN SCANSTATE.EXE ON A REMOTE PC FOR A SPECIFIC USER. 
ECHO.

:EXPORTTARGETPC
SET ECOMPNAME=0
SET /P ECOMPNAME="TARGET PC NAME FOR MIGRATION EXPORT:"
IF %Ecompname% equ 0 GOTO EXPORTTARGETPC

:EXPORTTARGETUSER
:: Using the computer name from above, this section lists the c:\users dir for that PC to help find or check the username.
DIR \\%Ecompname%\c$\USERS
:: The next line confirms the PC is online to sace time and prevent issues later on.
IF %errorlevel% equ 1 ECHO "Computer offline, check the PC or retype name." && GOTO EXPORTTARGETPC
IF EXIST \\%Ecompname%\c$\Windows\syswow64 (SET EArch=amd64) ELSE (SET EArch=x86)
ECHO.
SET EUSERNA=0
SET /P EUSERNA="ENTER USERNAME FOR MIGRATION EXPORT:"
IF %EUSERNA% equ 0 GOTO EXPORTTARGETUSER

:EXPORTEXECUTE
:: The command below uses PSEXEC to run the USMT command as the SYSTEM account on the target computer via the -s argument.
:: This is to avoid exit code -1073741515 which may be related to a system dll but be too generic to troubleshoot well.
:: However, using the system account means the USMT tools cannot write to network shares. It is able to run the exe off the share which is odd but works.
:: If a share is specified (StoreDir) then USMT fails noting the store path is invalid and stops.
:: To get round creating the migration file on a share, the command exports to c:\usmt which it creates automatically. The subfolder is then named after the specified user to better identify the folder.
:: This also allows the command to keep running and migration file to be created if the PC goes offline during this process.
:: To backup/make the migration file usable it is copied to a network share (StoreDir) using the account of the user running this script. 
:: If the user does not have admin rights to run psexec and/or to access the share this will fail.
:: All static variables can be checked, edited, or set in the Variables block above.
:: Note that the migration file is not deleted from the target PC. This allows copying it manually but this should be avoided as other steps are missed.
:: The commands used are:
::	PSEXEC:
::		-s : Use the system account on target PC to run the command.
::		-accepteula : bypass accepting the PSEXEC EULA if needed on first run.
::	SCANSTATE.EXE
::    Syntax:
::		SCANSTATE.EXE [store directory] [user account restrictions for migration] /o /c [configuration xml files] /localonly
:: 		There is a better list of these arguments from MSFT or on other sites, see the link in line 5 above but:
:: [store directory] is the file location for the exported migration file. This should be the local path C:\USMT
:: [user account restrictions for migration]
::	  /UI is users to include. This uses the input user account from above for the [domain].
::	  /UE is users to exclude. Althogh UI takes priority this is set to exlude all users on all domains (could also be "*\*" as in domain\user)
::	/o  is to overwrite any previous migration files at the store directory. This is helpful for testing but should be moot for one off PCs as it stores the file locally.
::	/c  is to continue upon non fatal errors. This was necessary as each setting or file that "fails" but is not critical prompts a non fatal error and cancels the entire process.
::  /i  specifies configuraton XML files and can be used many times to specify manyconfig files. 
::      This process uses the default migapp and miguser xml config files though this can be set to a custom file if one is created for our environment.
::  /localonly specifies migrating files only on the local PC regardless of xml config options. This will include only local disks not data on removable or mapped drives. 
::      The migration still includes mapped drives just not any data on them.

psexec \\%Ecompname% -s %USMTDir%\%EArch%\scanstate.EXE c:\usmt\%Euserna% /ui:[domain]\%Euserna% /UE:* /o /c /i:%USMTDir%\%EArch%\miguser.xml /i:%USMTDir%\%EArch%\migapp.xml /localonly
:: Copy USMT MIG file to share.
ROBOCOPY \\%Ecompname%\c$\usmt %StoreDir% /e
:: Copy Chrome Bookmarks to share.
ROBOCOPY "\\%Ecompname%\c$\Users\%EUSERNA%\%ChromeDir%" "%StoreDir%\%EUSERNA%\Chrome" bookm*.*
:: If Windows 7 sticky notes exist, copy them to share
:: https://www.thewindowsclub.com/import-sticky-notes-windows-7-to-10
IF Exist "\\%Ecompname%\c$\Users\%EUSERNA%\AppData\Roaming\Microsoft\Sticky Notes" (
	ROBOCOPY "\\%Ecompname%\c$\Users\%EUSERNA%\AppData\Roaming\Microsoft\Sticky Notes" "%StoreDir%\%EUSERNA%\StickyNotes\7" /e
	REN "%StoreDir%\%EUSERNA%\StickyNotes\7\StickyNotes.snt" ThresholdNotes.snt)
:: If windows 10 sticky notes exist, copy them to share
IF Exist "\\%Ecompname%\c$\Users\%EUSERNA%\%stickydir%" (ROBOCOPY "\\%Ecompname%\c$\Users\%EUSERNA%\%stickydir%\localstate" "%StoreDir%\%EUSERNA%\StickyNotes\10" /e)
:: Export Printers to file
C:\Windows\System32\spool\tools\PrintBRM.exe -b -noacl -s \\%ECOMPNAME% -f %StoreDir%\%EUSERNA%\printers.printerexport


ECHO.
ECHO ----------------------------------------------------------------------------------------------------------
ECHO PROFILE EXPORT FINISHED ON %ECOMPNAME% FOR %EUSERNA%. CHECK %StoreDir% FOR MIGRATION DATA
ECHO ----------------------------------------------------------------------------------------------------------
ECHO.
GOTO SCANORLOAD
:: This is the end of the SCANSTATE export process. It redirects to the scanorload option. 


:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::


:IMPORTLOADSTATESTART
ECHO.
ECHO THIS TOOL ALLOWS YOU TO REMOTELY IMPORT A PREVIOUS SCANSTATE EXPORT USING LOADSTATE.EXE.
ECHO.

:IMPORTTARGETPC
SET ICOMPNAME=0
SET /P ICOMPNAME="TARGET PC NAME FOR MIGRATION IMPORT:"
IF %Icompname% equ 0 GOTO IMPORTTARGETPC
DIR \\%Icompname%\c$>nul
IF %errorlevel% equ 1 ECHO "Computer offline, check the PC or retype name." && GOTO IMPORTTARGETPC
IF EXIST \\%Icompname%\c$\Windows\syswow64 (SET IArch=amd64) ELSE (SET IArch=x86)


:IMPORTTARGETUSER
SET IUSERNA=0
SET /P IUSERNA="ENTER USERNAME FOR MIGRATION IMPORT:"
DIR %StoreDir%\%iuserna%>nul
IF %errorlevel% equ 1 ECHO "A migration folder does not exist for that user." && GOTO IMPORTTARGETUSER
IF %IUSERNA% equ 0 GOTO IMPORTTARGETUSER 

:IMPORTCOPYMIGRATIONTOTARGET
:: This command relies on the migration file having already been created and copied to the StoreDir with the username specified in the prior code block. The file can be copied in manually if needed.
ROBOCOPY %StoreDir%\%IUSERNA% \\%Icompname%\c$\usmt\%IUSERNA% /mir

:IMPORTEXECUTE
:: The same notes for EXPORTEXECUTE apply here for how USMT and PSExec work together. Note the syntax here puts the store directory near the end of the command.
:: The arguments used are:
::	PSEXEC:
::		-s : Use the system account on target PC to run the command
::		-accepteula : bypass accepting the PSEXEC EULA if needed
::	LOADSTATE.EXE
::		LOADSTATE.EXE [configuration xml files] [store directory] /ALL /c
:: 		There is a better list of these arguments from MSFT or on other sites but:
::  /i  specifies cofniguraton XML files and can be used many times to specify manyconfig files. 
::      This is used for teh default migapp and miguser xml config files though this can bve set to a custom file if one is created for our environment.
::  [store directory] is the file location for the exported migration file. For the load state this is from the location where the ROBOCOPY command above copied the specified users migration data.
::	/ALL imports all users/settings/etc instead of just a specific user. If SCANSTATE is used to pick up all users (/UI:* or /UI:[domain]\*) all user profiles and data will be imported. 
::	/c  is to continue upon non fatal errors. This was necessary as each setting or file that "fails" prompts a non fatal error and cancels the entire process.

PSEXEC \\%ICOMPNAME% -S %USMTDir%\%IArch%\loadstate.EXE /i:%USMTDir%\%IArch%\migAPP.xml /i:%USMTDir%\%IArch%\migUSER.xml c:\usmt\%IUSERNA% /ALL /C
:: Import Chrome bookmarks, if exist.
If Exist "%StoreDir%\%IUSERNA%\Chrome" (ROBOCOPY "%StoreDir%\%IUSERNA%\Chrome" "\\%Icompname%\c$\Users\%IUSERNA%\%Chromedir%" /e)
:: Import sticky notes from 7, if exist. Not working. Must be done manually after logon.
If Exist "%StoreDir%\%IUSERNA%\StickyNotes\7" (ROBOCOPY  "%StoreDir%\%IUSERNA%\StickyNotes\7" "\\%Icompname%\c$\Users\%IUSERNA%\%stickydir%\localstate\Legacy" ThresholdNotes.snt)
:: Import sticky notes from 10, if exist. Not working. Must be done manually after logon.
If Exist "%StoreDir%\%IUSERNA%\StickyNotes\10" (ROBOCOPY "%StoreDir%\%IUSERNA%\StickyNotes\10" "\\%Icompname%\c$\Users\%IUSERNA%\%stickydir%\localstate" /e)
:: Copy Sticky Notes shortcut to target PC C:\USMT
ROBOCOPY "\\eugene-1\shared\ITStuff\USMT" "\\%Icompname%\c$\usmt" "Sticky Notes Dir.Lnk"
ROBOCOPY "\\eugene-1\shared\ITStuff\USMT" "\\%Icompname%\c$\usmt" "Stickycopy.bat"
ROBOCOPY "\\eugene-1\shared\ITStuff\USMT" "\\%Icompname%\c$\usmt" "Sticky Notes.lnk"

:: Import Printers from file (Not working, import manually.)
::If Exist "\\%ICOMPNAME%\C$\USMT\%IUSERNA%\printers.printerexport" (psexec \\%ICOMPNAME% C:\Windows\System32\spool\tools\Printbrm.exe -r -s \\%ICOMPNAME% -f C:\USMT\%IUSERNA%\printers.printerexport)


ECHO.
ECHO ----------------------------------------------------------------------------------------------------------
ECHO PROFILE IMPORT FINISHED ON %ICOMPNAME% FOR %IUSERNA%.
ECHO ----------------------------------------------------------------------------------------------------------
ECHO.
PAUSE

:IMPORTDELETELOCALMIGRATIONFILE
:: This option allows deleting the migration store from where robocpy copied it on the target PC. Recommended to save disk space but not required.
::ECHO 
::SET DELETE=0
::SET /P DELETE="DO YOU WANT TO DELETE THE MIGRATION DATA COPIED TO THE LOCAL PC? Y/N: "
::IF /I "%DELETE%" EQU "Y" RMDIR \\%ICOMPNAME%\C$\USMT\usmt /S /Q
::IF /I "%DELETE%" EQU "N" ECHO MIGRATION FILE NOT DELETED
::PAUSE
::GOTO SCANORLOAD

:EOF
:: End of File. After the PAUSE the script starts at the option to pick SCAN- or LOADSTATE
ECHO.
ECHO END OF SCRIPT
ECHO.
PAUSE
Goto SCANORLOAD

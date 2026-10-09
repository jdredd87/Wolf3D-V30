@ECHO OFF
REM Wolfenstein 3-D for the NEC V30 (80186 set) -- StevenC & Claude, 2026
REM Borland C++ 3.1 + TASM 3.1. BCC and TLINK are DPMI programs (286+), so
REM this runs on a 286 or better; the EXE it makes needs a V20/V30 or 186+.
REM No IF ... ECHO ... >> FILE: COMMAND.COM opens the redirect BEFORE it
REM tests the IF, so a false condition still creates an empty file.
REM Output: WOLF3DV.EXE + WOLF3DV.MAP, and BUILD.LOG holding everything the
REM tools printed (redirecting a CALLed batch does nothing in COMMAND.COM).
REM Any failure is listed in BUILD.ERR and appended to BUILD.LOG.
IF EXIST BUILD.LOG DEL BUILD.LOG
IF EXIST BUILD.ERR DEL BUILD.ERR
IF EXIST WOLF3DV.EXE DEL WOLF3DV.EXE
FOR %%F IN (C0 H_LDIV WL_ASM WL_DR_A ID_SD_A ID_US_A ID_VL_A ID_VH_A WL_SC_A ID_PM_A WL_NETA) DO CALL AS86.BAT %%F
FOR %%F IN (WL_MAIN WL_TEXT WL_MENU WL_INTER WL_GAME WL_PLAY WL_DEBUG WL_DRAW WL_SCALE WL_STATE WL_AGENT) DO CALL CC86.BAT %%F
FOR %%F IN (WL_ACT1 WL_ACT2 ID_CA ID_IN ID_MM ID_PM ID_SD ID_US_1 ID_VL ID_VH WL_PROF) DO CALL CC86.BAT %%F
REM WL_MP: no communal variables (-Fc-), so with its #pragma option -zE
REM every far variable shares one segment, not one each rounded up to 16
REM bytes (the 486 needs the memory).  One module only: id's WL_MENU.H
REM defines a variable (menuitems), and a second -Fc- module defines it twice
REM WL_MP and WL_NET for size (-G-, and -k-: no stack frame unneeded):
REM 991 bytes for the 486, and the V30 measured no slower (10.2 to 10.3)
CALL CC86.BAT WL_MP -Fc- -G- -k-
CALL CC86.BAT WL_NET -G- -k-
IF EXIST BUILD.ERR GOTO FAILED
C:\BCPP\BIN\TLINK.EXE @LINK86.RSP >> BUILD.LOG
IF ERRORLEVEL 1 GOTO LINKBAD
ECHO ##BUILD OK >> BUILD.LOG
GOTO END
:LINKBAD
ECHO ##FAIL TLINK >> BUILD.ERR
:FAILED
TYPE BUILD.ERR >> BUILD.LOG
:END

@ECHO OFF
REM Wolfenstein 3-D: the showcase -- a demo reel of every version, mode and
REM ability, for recording.  Written by launcher\mkshow.py (StevenC & Claude).
C:
CD \WOLF3D
IF EXIST SHOWSUM.TXT DEL SHOWSUM.TXT
IF EXIST SHOWQ.FLG DEL SHOWQ.FLG
IF EXIST SHOWCPU.TXT DEL SHOWCPU.TXT
IF EXIST W3MENU.EXE W3MENU /CPU > SHOWCPU.TXT
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   The showcase: id Software's original code first, then a version
ECHO   with every one of its modes, 60 seconds of the game's demos each.
ECHO.
ECHO     V  WOLF3DV -- id's picture exactly, and every detail option
ECHO     B  WOLF3DB -- far walls in less detail, and every detail option
ECHO     T  WOLF3DB with the BSP tree finding the walls
ECHO     A  all three, one after another
ECHO     Q  quit
ECHO.
CHOICE /C:VBTAQ /N    Which? 
IF ERRORLEVEL 5 GOTO END
IF ERRORLEVEL 4 GOTO ALL
IF ERRORLEVEL 3 GOTO T
IF ERRORLEVEL 2 GOTO B
CALL SHOWO
IF EXIST SHOWQ.FLG GOTO END
CALL SHOWV
GOTO END
:B
CALL SHOWO
IF EXIST SHOWQ.FLG GOTO END
CALL SHOWB
GOTO END
:T
CALL SHOWO
IF EXIST SHOWQ.FLG GOTO END
CALL SHOWT
GOTO END
:ALL
CALL SHOWO
IF EXIST SHOWQ.FLG GOTO END
CALL SHOWV
IF EXIST SHOWQ.FLG GOTO END
CALL SHOWB
IF EXIST SHOWQ.FLG GOTO END
CALL SHOWT
:END
IF EXIST SHOWQ.FLG DEL SHOWQ.FLG
IF NOT EXIST SHOWSUM.TXT GOTO BYE
CLS
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   -- every run, its frames and speed over 60 seconds of play:
ECHO.
TYPE SHOWSUM.TXT
ECHO.
ECHO   ORIGINAL is id's own code; WOLF3DV's full detail is its picture exactly.
:BYE

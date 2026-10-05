@ECHO OFF
REM Wolfenstein 3-D: the showcase's ORIGINAL reel.
REM Written by launcher\mkshow.py (StevenC & Claude): edit that, not this.
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO   ID'S ORIGINAL CODE
ECHO.
ECHO   1 of 1:  ID SOFTWARE'S ORIGINAL CODE  (1992)
ECHO.
ECHO   id's own renderer and game code, rebuilt for the 8086 (the original
ECHO   needs a 286).  The speed everything after this is measured against.
ECHO.
ECHO   180 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DO TIMEDEMO PRELOAD SECS 180
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DO TIMEDEMO PRELOAD SECS 180 > SHOWRES.TXT
CLS
ECHO.
ECHO   ID'S ORIGINAL CODE -- ID SOFTWARE'S ORIGINAL CODE  (1992)
ECHO.
TYPE SHOWRES.TXT
ECHO ORIGINAL: ID SOFTWARE'S ORIGINAL CODE  (1992) >> SHOWSUM.TXT
FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO QUIT
GOTO END
:QUIT
ECHO Q > SHOWQ.FLG
:END

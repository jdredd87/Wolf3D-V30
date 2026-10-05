@ECHO OFF
REM Wolfenstein 3-D: the showcase's BSP reel.
REM Written by launcher\mkshow.py (StevenC & Claude): edit that, not this.
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO   WOLF3DB with the BSP tree
ECHO.
ECHO   1 of 6:  THE BSP TREE  (as the SNES version)
ECHO.
ECHO   The walls found by a tree built from the level, front to back,
ECHO   instead of id's rays.  Far walls in less detail.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB with the BSP tree -- THE BSP TREE  (as the SNES version)
ECHO.
TYPE SHOWRES.TXT
ECHO BSP: THE BSP TREE  (as the SNES version) >> SHOWSUM.TXT
FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO QUIT
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO   WOLF3DB with the BSP tree
ECHO.
ECHO   2 of 6:  THE BSP TREE, full detail
ECHO.
ECHO   The tree, every wall at full detail.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP NOLOD
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP NOLOD > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB with the BSP tree -- THE BSP TREE, full detail
ECHO.
TYPE SHOWRES.TXT
ECHO BSP: THE BSP TREE, full detail >> SHOWSUM.TXT
FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO QUIT
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO   WOLF3DB with the BSP tree
ECHO.
ECHO   3 of 6:  BSP and LOWSPRITES
ECHO.
ECHO   The tree, enemies and items in two-pixel columns.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP LOWSPRITES
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP LOWSPRITES > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB with the BSP tree -- BSP and LOWSPRITES
ECHO.
TYPE SHOWRES.TXT
ECHO BSP: BSP and LOWSPRITES >> SHOWSUM.TXT
FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO QUIT
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO   WOLF3DB with the BSP tree
ECHO.
ECHO   4 of 6:  BSP and LOWVERT
ECHO.
ECHO   The tree, half the rows.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP LOWVERT
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP LOWVERT > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB with the BSP tree -- BSP and LOWVERT
ECHO.
TYPE SHOWRES.TXT
ECHO BSP: BSP and LOWVERT >> SHOWSUM.TXT
FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO QUIT
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO   WOLF3DB with the BSP tree
ECHO.
ECHO   5 of 6:  BSP, LOWSPRITES, LOWVERT, FASTOPL
ECHO.
ECHO   The tree with every option it draws itself.  (The wall options --
ECHO   LOWWALLS, FLATWALLS -- go back to id's rays, which are faster.)
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP LOWSPRITES LOWVERT FASTOPL
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP LOWSPRITES LOWVERT FASTOPL > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB with the BSP tree -- BSP, LOWSPRITES, LOWVERT, FASTOPL
ECHO.
TYPE SHOWRES.TXT
ECHO BSP: BSP, LOWSPRITES, LOWVERT, FASTOPL >> SHOWSUM.TXT
FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO QUIT
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO   WOLF3DB with the BSP tree
ECHO.
ECHO   6 of 6:  BSP and THE MAP
ECHO.
ECHO   The tree, with the map up: the walls it drew are what is explored.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP AUTOMAP
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 BSP AUTOMAP > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB with the BSP tree -- BSP and THE MAP
ECHO.
TYPE SHOWRES.TXT
ECHO BSP: BSP and THE MAP >> SHOWSUM.TXT
FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO QUIT
GOTO END
:QUIT
ECHO Q > SHOWQ.FLG
:END

@ECHO OFF
REM Wolfenstein 3-D for the NEC V30: a demo reel of the detail switches.
REM Written by launcher\mkshow.py (StevenC & Claude): edit that, not this.
C:
CD \WOLF3D
IF EXIST SHOWSUM1.TXT DEL SHOWSUM1.TXT
IF EXIST SHOWSUM2.TXT DEL SHOWSUM2.TXT
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 1 of 9:  FULL DETAIL -- id's own picture
ECHO.
ECHO   None of our options: every pixel as id Software's 1992 renderer
ECHO   draws it.  The starting point -- every run after this is faster.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 1 of 9:  FULL DETAIL -- id's own picture
ECHO.
TYPE SHOWRES.TXT
ECHO 1. FULL DETAIL -- id's own picture >> SHOWSUM1.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM1.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 2 of 9:  LOWSPRITES
ECHO.
ECHO   Enemies and items in two-pixel-wide columns.
ECHO   The walls stay as they are.  A small gain.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWSPRITES
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWSPRITES > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 2 of 9:  LOWSPRITES
ECHO.
TYPE SHOWRES.TXT
ECHO 2. LOWSPRITES >> SHOWSUM1.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM1.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 3 of 9:  FLATWALLS
ECHO.
ECHO   Every wall one solid colour, the texture's own, kept apart from
ECHO   floor and ceiling.  The artwork -- portraits, banners -- stays.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60 FLATWALLS
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 FLATWALLS > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 3 of 9:  FLATWALLS
ECHO.
TYPE SHOWRES.TXT
ECHO 3. FLATWALLS >> SHOWSUM1.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM1.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 4 of 9:  LOWVERT
ECHO.
ECHO   Half the vertical resolution: the VGA shows every other row,
ECHO   each twice as tall.  Walls, enemies and the gun lose half their rows.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWVERT
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWVERT > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 4 of 9:  LOWVERT
ECHO.
TYPE SHOWRES.TXT
ECHO 4. LOWVERT >> SHOWSUM1.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM1.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 5 of 9:  LOWWALLS
ECHO.
ECHO   One ray for every two screen columns: walls in two-pixel columns.
ECHO   The biggest single option.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWWALLS
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWWALLS > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 5 of 9:  LOWWALLS
ECHO.
TYPE SHOWRES.TXT
ECHO 5. LOWWALLS >> SHOWSUM1.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM1.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 6 of 9:  LOWDETAIL  (LOWWALLS and LOWSPRITES)
ECHO.
ECHO   Walls, enemies and items all in two-pixel columns.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWDETAIL
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWDETAIL > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 6 of 9:  LOWDETAIL  (LOWWALLS and LOWSPRITES)
ECHO.
TYPE SHOWRES.TXT
ECHO 6. LOWDETAIL  (LOWWALLS and LOWSPRITES) >> SHOWSUM2.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM2.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 7 of 9:  LOWDETAIL and FLATWALLS
ECHO.
ECHO   Two-pixel columns, and solid-colour walls.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWDETAIL FLATWALLS
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWDETAIL FLATWALLS > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 7 of 9:  LOWDETAIL and FLATWALLS
ECHO.
TYPE SHOWRES.TXT
ECHO 7. LOWDETAIL and FLATWALLS >> SHOWSUM2.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM2.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 8 of 9:  LOWDETAIL and LOWVERT
ECHO.
ECHO   Two-pixel columns and half the rows: a quarter of the view's pixels.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWDETAIL LOWVERT
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWDETAIL LOWVERT > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 8 of 9:  LOWDETAIL and LOWVERT
ECHO.
TYPE SHOWRES.TXT
ECHO 8. LOWDETAIL and LOWVERT >> SHOWSUM2.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM2.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  StevenC and Claude
ECHO   ------------------------------------------------------------------
ECHO.
ECHO   Demo 9 of 9:  EVERYTHING  (LOWDETAIL, FLATART, LOWVERT)
ECHO.
ECHO   All of it at once, artwork walls solid too.  The fastest.
ECHO.
ECHO   60 seconds of the game's demo 0, then the speed: the faster
ECHO   the mode, the further it gets in the same time.
ECHO.
ECHO   WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWDETAIL FLATART LOWVERT
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO END
WOLF3DV TIMEDEMO PRELOAD SECS 60 LOWDETAIL FLATART LOWVERT > SHOWRES.TXT
CLS
ECHO.
ECHO   Demo 9 of 9:  EVERYTHING  (LOWDETAIL, FLATART, LOWVERT)
ECHO.
TYPE SHOWRES.TXT
ECHO 9. EVERYTHING  (LOWDETAIL, FLATART, LOWVERT) >> SHOWSUM2.TXT
FIND "demo 0" < SHOWRES.TXT >> SHOWSUM2.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO END
:END
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  the runs, 1 of 2:
ECHO.
IF EXIST SHOWSUM1.TXT TYPE SHOWSUM1.TXT
ECHO.
CHOICE /C:SQ /N /T:S,15 > NUL
CLS
ECHO.
ECHO   Wolfenstein 3-D on an NEC V30  --  the runs, 2 of 2:
ECHO.
IF EXIST SHOWSUM2.TXT TYPE SHOWSUM2.TXT
ECHO.
ECHO   Full detail is id's picture exactly; every switch is optional.

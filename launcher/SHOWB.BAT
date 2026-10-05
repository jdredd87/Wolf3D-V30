@ECHO OFF
REM Wolfenstein 3-D: the showcase's WOLF3DB reel.
REM Written by launcher\mkshow.py (StevenC & Claude): edit that, not this.
CLS
ECHO.
ECHO   Wolfenstein 3-D  --  optimized by StevenC and Claude
IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT
ECHO   ------------------------------------------------------------------
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   1 of 13:  FAR WALLS IN LESS DETAIL  (the default)
ECHO.
ECHO   id's rays, but a wall under 64 pixels tall is textured every second
ECHO   column, under 32 every fourth.  Near walls and every edge exact.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- FAR WALLS IN LESS DETAIL  (the default)
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: FAR WALLS IN LESS DETAIL  (the default) >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   2 of 13:  NOLOD  (full detail)
ECHO.
ECHO   The same program with every wall at full detail: id's picture.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 NOLOD
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 NOLOD > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- NOLOD  (full detail)
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: NOLOD  (full detail) >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   3 of 13:  LOWSPRITES
ECHO.
ECHO   Enemies and items in two-pixel-wide columns.
ECHO   The walls stay as they are.  A small gain.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWSPRITES
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWSPRITES > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- LOWSPRITES
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: LOWSPRITES >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   4 of 13:  FARBLOBS
ECHO.
ECHO   Distant enemies and items as flat shapes, each run of pixels
ECHO   in its middle colour.  For faster machines.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 FARBLOBS
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 FARBLOBS > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- FARBLOBS
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: FARBLOBS >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   5 of 13:  FLATWALLS
ECHO.
ECHO   Every wall one solid colour, its texture's own, kept apart from
ECHO   floor and ceiling.  The artwork -- portraits, banners -- stays.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 FLATWALLS
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 FLATWALLS > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- FLATWALLS
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: FLATWALLS >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   6 of 13:  FLATART
ECHO.
ECHO   The artwork solid too.  The elevator switch, the way out,
ECHO   turns magenta so it can still be found.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 FLATART
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 FLATART > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- FLATART
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: FLATART >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   7 of 13:  LOWVERT
ECHO.
ECHO   Half the vertical resolution: the VGA shows every other row,
ECHO   each twice as tall.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWVERT
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWVERT > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- LOWVERT
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: LOWVERT >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   8 of 13:  LOWWALLS
ECHO.
ECHO   One ray for every two screen columns: walls in two-pixel columns.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWWALLS
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWWALLS > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- LOWWALLS
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: LOWWALLS >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   9 of 13:  LOWWALLS4
ECHO.
ECHO   One ray in four: walls in four-pixel columns.
ECHO   The biggest single option on a V30.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWWALLS4
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWWALLS4 > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- LOWWALLS4
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: LOWWALLS4 >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   10 of 13:  LOWDETAIL  (LOWWALLS and LOWSPRITES)
ECHO.
ECHO   Walls, enemies and items all in two-pixel columns.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWDETAIL
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWDETAIL > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- LOWDETAIL  (LOWWALLS and LOWSPRITES)
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: LOWDETAIL  (LOWWALLS and LOWSPRITES) >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   11 of 13:  LOWDETAIL and LOWVERT
ECHO.
ECHO   Two-pixel columns and half the rows: a quarter of the view's pixels.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWDETAIL LOWVERT
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWDETAIL LOWVERT > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- LOWDETAIL and LOWVERT
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: LOWDETAIL and LOWVERT >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   12 of 13:  EVERYTHING
ECHO.
ECHO   Four-pixel walls, two-pixel sprites, solid colours, half the rows,
ECHO   flat far sprites and AdLib with no waits.  The fastest.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWWALLS4 LOWSPRITES FLATART LOWVERT FARBLOBS FASTOPL
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 LOWWALLS4 LOWSPRITES FLATART LOWVERT FARBLOBS FASTOPL > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- EVERYTHING
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: EVERYTHING >> SHOWSUM.TXT
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
ECHO   WOLF3DB -- the faster version
ECHO.
ECHO   13 of 13:  THE MAP  (TAB in the game)
ECHO.
ECHO   The rooms explored, walls, doors in their keys' colours, items,
ECHO   enemies in sight and the player.  The game goes on under it.
ECHO.
ECHO   60 seconds of the game's own demos, then the speed: the faster
ECHO   the mode, the further it gets.
ECHO.
ECHO   WOLF3DB TIMEDEMO PRELOAD SECS 60 AUTOMAP
ECHO.
ECHO   Starting in 8 seconds  (S starts it now, Q quits)
CHOICE /C:SQ /N /T:S,08 > NUL
IF ERRORLEVEL 2 GOTO QUIT
WOLF3DB TIMEDEMO PRELOAD SECS 60 AUTOMAP > SHOWRES.TXT
CLS
ECHO.
ECHO   WOLF3DB -- the faster version -- THE MAP  (TAB in the game)
ECHO.
TYPE SHOWRES.TXT
ECHO WOLF3DB: THE MAP  (TAB in the game) >> SHOWSUM.TXT
FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT
ECHO.
ECHO   Next in 10 seconds  (S goes on now, Q quits)
CHOICE /C:SQ /N /T:S,10 > NUL
IF ERRORLEVEL 2 GOTO QUIT
GOTO END
:QUIT
ECHO Q > SHOWQ.FLG
:END

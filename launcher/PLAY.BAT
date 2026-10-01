@ECHO OFF
REM Wolfenstein 3-D for the NEC V30: the detail switches menu, W3MENU.EXE
REM (StevenC & Claude).  W3MENU exits 0 having written W3RUN.BAT, or 1 to quit.
C:
CD \WOLF3D
:MENU
W3MENU %1 %2
IF ERRORLEVEL 1 GOTO END
CALL W3RUN.BAT
GOTO MENU
:END

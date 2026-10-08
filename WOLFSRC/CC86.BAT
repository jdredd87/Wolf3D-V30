@ECHO OFF
REM Wolfenstein 3-D for the NEC V30 (80186 set) -- StevenC & Claude, 2026
REM Borland C++ 3.1 + TASM 3.1. BCC and TLINK are DPMI programs (286+), so
REM this runs on a 286 or better; the EXE it makes needs a V20/V30 or 186+.
REM No IF ... ECHO ... >> FILE: COMMAND.COM opens the redirect BEFORE it
REM tests the IF, so a false condition still creates an empty file.
C:\BCPP\BIN\BCC.EXE -c %2 %1.C >> BUILD.LOG
IF ERRORLEVEL 1 GOTO BAD
GOTO END
:BAD
ECHO ##FAIL %1.C >> BUILD.ERR
:END

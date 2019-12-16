@echo off
setlocal

set controlsFile="controls_nibe_heatpump.txt"

type nul > %controlsFile%
CALL :appendLines "FHEM/98_NIBE_HEATPUMP.pm"
CALL :appendLines "www/images/fhemSVG/nibe_heatpump.svg"
CALL :appendLines "www/images/fhemSVG/nibe_mode_default.svg"
CALL :appendLines "www/images/fhemSVG/nibe_mode_away.svg"
CALL :appendLines "www/images/fhemSVG/nibe_mode_vacation.svg"
EXIT /B %ERRORLEVEL%

:appendLines
set file=%*;

FOR /F "usebackq" %%A IN ('%file%') DO set size=%%~zA
echo.File is %size% bytes

set hour=%time:~0,2%
if "%hour:~0,1%" == " " set hour=0%hour:~1,1%
set min=%time:~3,2%
if "%min:~0,1%" == " " set min=0%min:~1,1%
set secs=%time:~6,2%
if "%secs:~0,1%" == " " set secs=0%secs:~1,1%
set year=%date:~-4%
set month=%date:~3,2%
if "%month:~0,1%" == " " set month=0%month:~1,1%
set day=%date:~0,2%
if "%day:~0,1%" == " " set day=0%day:~1,1%
set datetime=%year%-%month%-%day%_%hour%:%min%:%secs%
echo.Datetime is %datetime%

@echo DEL ./%file:"=%>> %controlsFile%
@echo UPD %datetime% %size:"=% %file:"=%>> %controlsFile%

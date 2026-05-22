@echo off
setlocal enabledelayedexpansion

:: Build script for Pragtical
:: Usage: build.bat [buildtype] [clean] [-h]
::   buildtype:    release (default), debugoptimized
::   clean|--clean: remove build\ and pragtical\ and exit
::   -h|--help:    show usage and exit

set "buildtype=release"
set "clean=false"

:parse_args
if "%~1"=="" goto end_parse
if "%~1"=="-h" goto show_help
if "%~1"=="--help" goto show_help
if "%~1"=="clean" (
    set "clean=true"
) else if "%~1"=="--clean" (
    set "clean=true"
) else if not "%~1"=="" (
    set "buildtype=%~1"
)
shift
goto parse_args

:show_help
echo Usage: build.bat [buildtype] [clean] [-h]
echo.
echo   buildtype       Build type to pass to Meson (default: release)
echo                   Examples: release, debugoptimized, debug
echo   clean, --clean  Remove build\ and pragtical\ directories and exit
echo   -h, --help      Show this help message and exit
exit /b 0

:end_parse

if "%clean%"=="true" (
    echo Cleaning build artifacts...
    if exist "build" rd /s /q "build"
    if exist "pragtical" rd /s /q "pragtical"
    echo Done.
    exit /b 0
)

echo Building with buildtype=%buildtype%

if not exist "build\build.ninja" (
    meson setup --wrap-mode=forcefallback --buildtype=%buildtype% build
) else (
    echo Build directory exists, skipping setup...
)

meson compile -C build
meson install -C build --skip-subprojects="freetype2,pcre2,sdl3" --destdir ../pragtical/

if exist "pragtical\lib" rd /s /q "pragtical\lib"
if exist "pragtical\include" rd /s /q "pragtical\include"
if exist "pragtical\doc" rd /s /q "pragtical\doc"
if exist "pragtical\user\README.md" del /q "pragtical\user\README.md"

echo Build complete! Output in pragtical/

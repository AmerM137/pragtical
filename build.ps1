# Build script for Pragtical
# Usage: .\build.ps1 [buildtype] [clean]
#   buildtype:    release (default), debugoptimized
#   clean|--clean: remove build/ and pragtical/ and exit

$buildtype = "release"
$clean = $false

foreach ($arg in $args) {
    if ($arg -eq "--clean" -or $arg -eq "clean") { $clean = $true }
    elseif ($arg -ne "") { $buildtype = $arg }
}

if ($clean) {
    Write-Host "Cleaning build artifacts..." -ForegroundColor Yellow
    if (Test-Path "build")      { Remove-Item -Recurse -Force "build" }
    if (Test-Path "pragtical")  { Remove-Item -Recurse -Force "pragtical" }
    Write-Host "Done." -ForegroundColor Green
    exit 0
}

Write-Host "Building with buildtype=$buildtype" -ForegroundColor Cyan

if (-not (Test-Path "build\build.ninja")) {
    meson setup --wrap-mode=forcefallback --buildtype=$buildtype -Dppm=false build
} else {
    Write-Host "Build directory exists, skipping setup..." -ForegroundColor DarkGray
}
meson compile -C build
meson install -C build --skip-subprojects="freetype2,pcre2,sdl3" --destdir ../pragtical/

Remove-Item -Recurse -Force -Path "pragtical/lib","pragtical/include","pragtical/doc" -ErrorAction SilentlyContinue
Remove-Item -Force "pragtical/user/README.md" -ErrorAction SilentlyContinue

Write-Host "Build complete! Output in pragtical/" -ForegroundColor Green

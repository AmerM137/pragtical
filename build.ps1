# Build script for Pragtical
# Usage: .\build.ps1 [buildtype] [clean] [-h]
#   buildtype:    release (default), debugoptimized
#   clean|--clean: remove build/ and pragtical/ and exit
#   -h|--help:    show usage and exit

$buildtype = "release"
$clean = $false

foreach ($arg in $args) {
    if ($arg -eq "-h" -or $arg -eq "--help") {
        Write-Host "Usage: .\build.ps1 [buildtype] [clean] [-h]"
        Write-Host ""
        Write-Host "  buildtype       Build type to pass to Meson (default: release)"
        Write-Host "                  Examples: release, debugoptimized, debug"
        Write-Host "  clean, --clean  Remove build/ and pragtical/ directories and exit"
        Write-Host "  -h, --help      Show this help message and exit"
        exit 0
    } elseif ($arg -eq "--clean" -or $arg -eq "clean") { $clean = $true }
    elseif ($arg -ne "") { $buildtype = $arg }
}

if ($clean) {
    Write-Host "Cleaning build artifacts..."
    if (Test-Path "build")      { Remove-Item -Recurse -Force "build" }
    if (Test-Path "pragtical")  { Remove-Item -Recurse -Force "pragtical" }
    Write-Host "Done."
    exit 0
}

Write-Host "Building with buildtype=$buildtype"

if (-not (Test-Path "build\build.ninja")) {
    meson setup --wrap-mode=forcefallback --buildtype=$buildtype build
} else {
    Write-Host "Build directory exists, skipping setup..."
}
meson compile -C build
meson install -C build --skip-subprojects="freetype2,pcre2,sdl3" --destdir ../pragtical/

Remove-Item -Recurse -Force -Path "pragtical/lib","pragtical/include","pragtical/doc" -ErrorAction SilentlyContinue
Remove-Item -Force "pragtical/user/README.md" -ErrorAction SilentlyContinue

# Remove unwanted plugins
Remove-Item -Force "pragtical/data/plugins/quote.lua","pragtical/data/plugins/reflow.lua","pragtical/data/plugins/macro.lua","pragtical/data/plugins/tabularize.lua","pragtical/data/plugins/language_xml.lua" -ErrorAction SilentlyContinue

Write-Host "Build complete! Output in pragtical/"

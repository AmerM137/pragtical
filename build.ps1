meson setup --wrap-mode=forcefallback --buildtype=release build
meson compile -C build
meson install -C build --skip-subprojects="freetype2,pcre2,sdl3" --destdir ../pragtical/

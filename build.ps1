meson setup --wrap-mode=forcefallback --buildtype=release build
meson compile -C build
meson install -C build --skip-subprojects="freetype2,pcre2,sdl2" --destdir ../pragtical/
mkdir ./pragtical/user

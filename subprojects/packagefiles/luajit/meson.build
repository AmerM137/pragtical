#
# Linux, Windows and Darwin build support taken from:
# https://github.com/arch1t3cht/Aegisub/tree/feature/subprojects/packagefiles/luajit
#
project('luajit',
    'c',
    version: '2.1.0',
    license: 'MIT',
    default_options : ['warning_level=0', 'werror=false']
)

cc = meson.get_compiler('c')

system = host_machine.system()

if system == 'linux' or system == 'darwin' or system == 'windows'
    system_deps = [
        cc.find_library('dl', required: false),
        cc.find_library('m', required: false)
    ]

    # get architecture id for the host machine so it can be set when compiling buildvm natively
    lj_target_id = cc.get_define(
        'LUAJIT_TARGET',
        prefix: '#include "@0@/src/lj_arch.h"'.format(meson.current_source_dir())
    )
    add_project_arguments(
        '-DLUAJIT_TARGET=@0@'.format(lj_target_id),
        language: 'c',
        native: true
    )

    # compat flag is needed for both the buildvm code generator (compiled natively) and luajit itself
    add_project_arguments(
        '-DLUAJIT_ENABLE_LUA52COMPAT',
        '-DENDIAN_LE',
        language: 'c',
        native: true
    )
    add_project_arguments(
        '-DLUAJIT_ENABLE_LUA52COMPAT',
        '-DENDIAN_LE',
        language: 'c',
        native: false
    )
    if host_machine.system() == 'linux'
        add_project_arguments(
            '-DLUAJIT_OS=LUAJIT_OS_LINUX',
            language: 'c',
            native: true
        )
        add_project_arguments(
            '-DLUAJIT_UNWIND_EXTERNAL',
            language: 'c',
            native: false
        )
        ljvm_mode = 'elfasm'
        ljvm_bout = 'lj_vm.s'
    elif host_machine.system() == 'darwin'
        add_project_arguments(
            '-DLUAJIT_OS=LUAJIT_OS_OSX',
            language: 'c',
            native: true
        )
        add_project_arguments(
            '-DLUAJIT_UNWIND_EXTERNAL',
            language: 'c',
            native: false
        )
        ljvm_mode = 'machasm'
        ljvm_bout = 'lj_vm.s'
    elif host_machine.system() == 'windows'
        add_project_arguments(
            '-DLUAJIT_OS=LUAJIT_OS_WINDOWS',
            language: 'c',
            native: true
        )
        if cc.get_id() != 'msvc'
            add_project_arguments('-malign-double', language: 'c', native: true)
        endif
        ljvm_mode = 'peobj'
        ljvm_bout = 'lj_vm.o'
    endif

    subdir('src')

    luajit_dep = declare_dependency(
        link_with: luajit_lib,
        include_directories: src_inc
    )
else
    make_command = find_program('make', required: false)

    if not make_command.found()
        error('Unsupported platform')
    endif

    build_command = [make_command, 'amalg']

    env = environment()

    if host_machine.system() == 'darwin'
        build_command += 'MACOSX_DEPLOYMENT_TARGET=10.11'
        if meson.is_cross_build()
            env.set('TARGET_CFLAGS', '-arch arm64')
            env.set('TARGET_LDFLAGS', '-arch arm64')
        endif
    endif

    build_command += [
        'CFLAGS=-fPIC',
        'XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT',
        'BUILDMODE=static', '-l', '90', '-j'
    ]

    run_command(build_command, check: true, env: env)

    cc = meson.get_compiler('c')

    luajit = cc.find_library('luajit',
        dirs: [ meson.current_source_dir() + '/src'],
        required: true,
        static: true
    )

    luajit_dep = declare_dependency(
        dependencies: luajit,
        include_directories: include_directories('src')
    )
endif

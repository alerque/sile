AC_PREREQ([2.69])
AC_INIT([sile], [m4_esyscmd(build-aux/git-version-gen .tarball-version)], [caleb@alerque.com])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_MACRO_DIR([build-aux])
AC_CANONICAL_TARGET
AM_INIT_AUTOMAKE([foreign tar-pax dist-zstd dist-zip no-dist-gzip no-dependencies color-tests subdir-objects])
AM_SILENT_RULES([yes])

# Load up re-usable m4 bits shared across Caleb's projects
QUE_GIT_VERSION
QUE_TRANSFORM_PACKAGE_NAME
QUE_DEVELOPER_MODE
QUE_DIST_CHECKSUMS
QUE_LIBEXT

# Extend the QUE checksums feature with support for the PDF manual
SILE_DIST_CHECKSUMS

# Check for and set variables for tooling used during our build process
AC_PROG_AWK
AC_PROG_CC
AC_PROG_GREP
AC_PROG_OBJC
AC_PROG_SED
AX_REQUIRE_PROG([cmp])
AX_REQUIRE_PROG([diff])
AX_REQUIRE_PROG([find])
AX_REQUIRE_PROG([head])
AX_REQUIRE_PROG([jq])
AX_REQUIRE_PROG([luarocks])
AX_REQUIRE_PROG([pdfinfo])
AX_REQUIRE_PROG([sort])
AX_REQUIRE_PROG([xargs])

# Disable ranlib to avoid it being run on our rusile.so module, already LTO
# optimized but libtool wants to relink it...
RANLIB=:

LT_PREREQ([2.2])
LT_INIT([dlopen])

QUE_DOCKER_BOILERPLATE
QUE_RUST_BOILERPLATE
QUE_RUST_MODULE([rusile])

AM_CONDITIONAL([SHARED], [test "x$enable_shared" = "xyes"])
AM_CONDITIONAL([STATIC], [test "x$enable_static" = "xyes"])

AC_ARG_ENABLE([embedded],
              AS_HELP_STRING([--enable-embedded-resources],
                             [Compile resources such as Lua module files directly into the Rust CLI binary]))
AM_CONDITIONAL([EMBEDDED_RESOURCES], [test "x$enable_embedded_resources" = "xyes"])

AC_ARG_ENABLE([font-variations],
              AS_HELP_STRING([--disable-font-variations],
                             [Disable support for OpenType variations and variable fonts that requires HarfBuzz subsetter library]))
AM_CONDITIONAL([FONT_VARIATIONS], [test "x$enable_font_variations" != "xno"])

AC_ARG_ENABLE([linklua],
              AS_HELP_STRING([--disable-linklua],
                             [Don’t link lua library with dylibs]))
AM_CONDITIONAL([LINKLUA], [test "x$enable_linklua" != "xno"])

# TODO: Refactor fontconfig check to allow Appkit/DirectWrite as alternatives, maybe default to off on Darwin
# AC_ARG_WITH([fontconfig],
#             AS_HELP_STRING([--without-fontconfig],
#                            [Compile without fontconfig font manager support]))
AM_CONDITIONAL([FONTCONFIG], [test "x$with_fontconfig" != "xno"])

AC_ARG_WITH([harfbuzz],
            AS_HELP_STRING([--without-harfbuzz],
                           [Compile without HarfBuzz support used as default shaping backend]))
AM_CONDITIONAL([HARFBUZZ], [test "x$with_harfbuzz" != "xno"])

AC_ARG_WITH([system-libtexpdf],
            AS_HELP_STRING([--with-system-libtexpdf],
                           [Don’t bundle libtexpdf, use system provided version]))
AM_CONDITIONAL([SYSTEM_LIBTEXPDF], [test "x$with_system_libtexpdf" = "xyes"])

AC_ARG_WITH([system-luarocks],
            AS_HELP_STRING([--with-system-luarocks],
                           [Don’t bundle LuaRocks, use system provided versions]))
AM_CONDITIONAL([SYSTEM_LUAROCKS], [test "x$with_system_luarocks" = "xyes"])
AC_SUBST([SYSTEM_LUAROCKS])

AC_ARG_WITH([vendored-luarocks-dir],
            AS_HELP_STRING([--with-vendored-luarocks-dir=PATH],
                           [Specify a custom vendored location from which to load ‘system’ luarocks]),
            [],
            [with_vendored_luarocks_dir=no])
AM_CONDITIONAL([VENDORED_LUAROCKS], [test "x$with_vendored_luarocks_dir" != "xno"])
AC_SUBST([VENDORED_LUAROCKS])

AC_ARG_WITH([system-lua-sources],
            AS_HELP_STRING([--with-system-lua-sources],
                           [Don’t compile against vendored Lua sources, use system headers]))
AM_CONDITIONAL([SYSTEM_LUA_SOURCES], [test "x$with_system_lua_sources" = "xyes"])
AC_SUBST([SYSTEM_LUA_SOURCES])

AC_ARG_WITH([manual],
            AS_HELP_STRING([--with-manual],
                           [Rebuild manual and install to system’s PDF documentation directory]))
AM_CONDITIONAL([MANUAL], [test "x$with_manual" = "xyes"])

AM_CONDITIONAL([FONT_DOWNLOAD_TOOLS], [test -z ${DEVELOPER_MODE_TRUE} || (test -z ${SOURCE_IS_DIST_TRUE} && test -z ${MANUAL_TRUE})])
AC_SUBST([FONT_DOWNLOAD_TOOLS])

AM_COND_IF([MANUAL], [
            AX_REQUIRE_PROG([dot])
            AX_REQUIRE_PROG([gs])
            ])

AC_MSG_CHECKING([for OS X])
have_appkit=no
case $target_os in
    darwin*)
        AC_MSG_RESULT([yes])
        AC_MSG_CHECKING([for AppKit works])
        save_LIBS="$LIBS"
        LIBS="$LIBS -framework AppKit  -fmodules"
        AC_LANG_PUSH([Objective C])
        AC_LINK_IFELSE([AC_LANG_PROGRAM([[@import AppKit;]],[[]])],
        [
            have_appkit=yes
            AC_MSG_RESULT([yes])
        ], [
            have_appkit=no
            AC_MSG_RESULT([no])
        ])
        AC_LANG_POP([Objective C])
        LIBS="$save_LIBS"
        ;;
    *)
        AC_MSG_RESULT([no])
        ;;
esac
AM_CONDITIONAL([APPKIT], [test "x$have_appkit" = "xyes"])

AM_COND_IF([FONTCONFIG],
            [PKG_CHECK_MODULES(FONTCONFIG, [fontconfig],
                                [],
                                [AC_MSG_FAILURE([Fontconfig package not found])])])

AM_COND_IF([HARFBUZZ],
            [PKG_CHECK_MODULES(HARFBUZZ, [harfbuzz >= 2.7.4],
                                [],
                                [AC_MSG_FAILURE([--with-harfbuzz was given, but harfbuzz not found])]) ])

AM_COND_IF([FONT_VARIATIONS],
            [PKG_CHECK_MODULES(HARFBUZZ_SUBSET, [harfbuzz-subset >= 6.0.0],
                                [AC_DEFINE(HAVE_HARFBUZZ_SUBSET, [1], [Have harfbuzz-subset library])],
                                [AC_MSG_FAILURE([--enable-font-variations was given, but harfbuzz version not new enough to include required subset library functions])])])

AM_COND_IF([SYSTEM_LIBTEXPDF],
            [AC_CHECK_LIB([texpdf], [texpdf_doc_set_verbose],
                            [],
                            [AC_MSG_FAILURE([--with-system-libtexpdf was given, but test for libtexpdf failed])])],
            [AC_CONFIG_SUBDIRS([libtexpdf])])

PKG_CHECK_MODULES(ICU, icu-uc icu-i18n icu-io, [
    with_icu=yes
],[
    AC_CHECK_TOOL(ICU_CONFIG, icu-config, no)
    AC_MSG_CHECKING([for ICU by using icu-config fallback])
    if test "$ICU_CONFIG" != "no" && "$ICU_CONFIG" --version >/dev/null; then
        ICU_LIBS=`icu-config  --ldflags-libsonly --ldflags-icuio`
        ICU_CFLAGS=`icu-config --cppflags`
        with_icu=yes
        AC_MSG_RESULT([yes])
    else
        AC_MSG_FAILURE([Required ICU library not found])
    fi
])
AM_CONDITIONAL([ICU], [test "x$with_icu" = "xyes"])

# Required for downloading fonts for the manual and for tests
# Since the source tarball includes a prebuilt manual we only need this for Git source builds
AM_COND_IF([FONT_DOWNLOAD_TOOLS], [
    AX_REQUIRE_PROG([bsdtar])
    AX_REQUIRE_PROG([curl])
])

AM_COND_IF([DEVELOPER_MODE], [
    AX_WITH_PROG([DELTA], [delta], [cat])
    AX_WITH_PROG([PERL], [perl])
])

AM_COND_IF([DEVELOPER_TOOLS], [
    AX_REQUIRE_PROG([busted])
    AX_REQUIRE_PROG([cargo-deny])
    AX_REQUIRE_PROG([cargo-set-version])
    AX_REQUIRE_PROG([curl])
    AX_REQUIRE_PROG([just])
    AX_REQUIRE_PROG([ldoc])
    AX_REQUIRE_PROG([luacheck])
    AX_REQUIRE_PROG([nix])
    AX_REQUIRE_PROG([npm])
    AX_REQUIRE_PROG([perl])
    AX_REQUIRE_PROG([stylua])
    AX_REQUIRE_PROG([taplo])
    AX_REQUIRE_PROG([tr])
    AX_REQUIRE_PROG([typos])
    AX_REQUIRE_PROG([xsltproc])
    AX_REQUIRE_PROG([zstd])
])

AX_PROG_LUA([5.1], [], [], [], [prefer])
AX_LUA_HEADERS
AX_LUA_LIBS

AM_COND_IF([SYSTEM_LUAROCKS], [
    AS_IF([test "$LUA_SHORT_VERSION" -lt 52], [
        AM_COND_IF([LUAJIT], [], [AX_LUA_MODULE(bit32)])
    ])
    AX_LUA_MODULE(cassowary)
    AS_IF([test "$LUA_SHORT_VERSION" -lt 53], [AX_LUA_MODULE(compat53)])
    AX_LUA_MODULE(cldr)
    AX_LUA_MODULE(fluent)
    AX_LUA_MODULE(linenoise)
    AX_LUA_MODULE(loadkit)
    AX_LUA_MODULE(lpeg)
    AX_LUA_MODULE(lua-zlib, zlib)
    AX_LUA_MODULE(lua_cliargs, cliargs)
    AX_LUA_MODULE(luaepnf, epnf)
    AX_LUA_MODULE(luaexpat, lxp)
    AX_LUA_MODULE(luafilesystem, lfs)
    AX_LUA_MODULE(luafilesystem)
    AX_LUA_MODULE(luarepl, repl)
    AX_LUA_MODULE(luasec, ssl)
    AX_LUA_MODULE(luasocket, socket)
    AX_LUA_MODULE(luautf8, lua-utf8)
    AX_LUA_MODULE(penlight, pl)
    AX_LUA_MODULE(vstruct)
], [
    AX_REQUIRE_PROG([git]) # required for luarocks to install zlib rock
])

QUE_FONT(Gentium Plus)

AC_SUBST([APPKIT_TRUE])
AC_SUBST([FONTCONFIG_TRUE])
AC_SUBST([FONT_VARIATIONS_TRUE])
AC_SUBST([HARFBUZZ_TRUE])
AC_SUBST([HARFBUZZ_CFLAGS])
AC_SUBST([HARFBUZZ_LIBS])
AC_SUBST([HARFBUZZ_SUBSET_CFLAGS])
AC_SUBST([HARFBUZZ_SUBSET_LIBS])
AC_SUBST([ICU_TRUE])
AC_SUBST([ICU_CFLAGS])
AC_SUBST([ICU_LIBS])
AC_SUBST([LUAROCKSARGS])

# Avoid need for `--datarootdir=$(cd ..; pwd)` hack to run locally for
# tests/manual build when developer mode is enabled
AM_COND_IF([DEVELOPER_MODE], [
    adl_RECURSIVE_EVAL(["$(pwd)"], [SILE_PATH])
    datarootdir="$(cd ..; pwd)"
],[
    adl_RECURSIVE_EVAL(["${datadir}/${TRANSFORMED_PACKAGE_NAME}"], [SILE_PATH])
])
AC_DEFINE_UNQUOTED([SILE_PATH], ["${SILE_PATH}"], [Path for SILE packages and classes])
AC_SUBST([SILE_PATH])

# In order for our Rust CLI binary to use the same default package.(c)path as the system Lua,
# we test the system Lua (required only at build not run time) for its current package.(c)path.
adl_RECURSIVE_EVAL(["$(${LUA} -e 'print(package.path)')"], [SYSTEM_LUA_PATH])
adl_RECURSIVE_EVAL(["$(${LUA} -e 'print(package.cpath)')"], [SYSTEM_LUA_CPATH])
AC_DEFINE_UNQUOTED([SYSTEM_LUA_PATH], ["${SYSTEM_LUA_PATH}"],[System Lua package path])
AC_DEFINE_UNQUOTED([SYSTEM_LUA_CPATH], ["${SYSTEM_LUA_CPATH}"], [System Lua package cpath])
AC_SUBST([SYSTEM_LUA_PATH])
AC_SUBST([SYSTEM_LUA_CPATH])

# Accommodate Homebrew and/or other distros that pretend a vendored location is the system.
AM_COND_IF([VENDORED_LUAROCKS],
        [VENDORED_LUAROCKS_DIR="$with_vendored_luarocks_dir"])
AC_SUBST([VENDORED_LUAROCKS_DIR])

adl_RECURSIVE_EVAL(["${libdir}/${TRANSFORMED_PACKAGE_NAME}"], [SILE_LIB_PATH])
AC_DEFINE_UNQUOTED([SILE_LIB_PATH],["${SILE_LIB_PATH}"], [Path for SILE libraries])
AC_SUBST([SILE_LIB_PATH])

AC_SUBST([ROCKSPECWARNING], ["DO NOT EDIT! Modify template sile.rockspec.in"])
AC_SUBST([ROCKREV], [1])

QUE_SUBST_MAN_DATE

AC_CONFIG_FILES([build-aux/list-distfiles.sh], [chmod +x build-aux/list-distfiles.sh])
AC_CONFIG_FILES([build-aux/import-tex-hyphens.sh], [chmod +x build-aux/import-tex-hyphens.sh])
AC_CONFIG_FILES([build-aux/transpile-tex-hyphen-patterns.lua], [chmod +x build-aux/transpile-tex-hyphen-patterns.lua])
AC_CONFIG_FILES([Makefile justenough/Makefile sile-lua.1 core/features.lua core/pathsetup.lua core/version.lua])
AC_CONFIG_FILES([sile-lua:sile.in], [chmod +x sile-lua])
AC_CONFIG_FILES([tests/regressions.pl], [chmod +x tests/regressions.pl])
AC_CONFIG_FILES([rusile-dev-1.rockspec:rusile.rockspec.in])
AC_CONFIG_FILES([sile-dev-1.rockspec:sile.rockspec.in])
AC_CONFIG_FILES([src/sile-entry.sh], [chmod +x src/sile-entry.sh])

AC_OUTPUT

AC_MSG_NOTICE([monkey-patching configure to ignore core directory])
m4_esyscmd_s([build-aux/decore-automake.sh])

# Avoid the perceived need to run automake again when building from source
# tarballs. The assorted AM include macros assume two passes are needed to
# generate a makefile since one pass has to generate the includes and the
# second one inlines them, but we're distributing a ready-to-use version and
# hence one pass is enough. We can skip ahead and assume the Makefile template
# is ready to go an this point, avoiding the need for autotools at all.
AM_COND_IF([SOURCE_IS_DIST], [touch -r aminclude.am Makefile.in])

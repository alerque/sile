dnl Note: requires AC_CANONICAL_TARGET to run before AC_INIT
AC_DEFUN_ONCE([QUE_LIBEXT], [
   AC_MSG_CHECKING([libext being derived])
   AC_MSG_RESULT([NOWISH])
    case $target_os in
        darwin*)
            LIBEXT=.dylib
            ;;
        cygwin*|mingw*)
            LIBEXT=.dll
            ;;
        *)
            LIBEXT=.so
        ;;
    esac
    AC_SUBST([LIBEXT])
])

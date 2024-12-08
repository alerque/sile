AC_DEFUN([AX_REQUIRE_PROG], [
    AC_PROG_SED
    pushdef([VARIABLE],m4_toupper(m4_translit($1,-.,__)))
    pushdef([EXECUTABLE],m4_default($2,$1))
    AX_WITH_PROG(VARIABLE,EXECUTABLE)
    AC_REQUIRE([VARIABLE])
    dnl AS_IF([test "x$with_$1" != xno && test -z "$VARIABLE"], [
    dnl     AC_MSG_ERROR([EXECUTABLE is required])
    dnl ])
    popdef([EXECUTABLE])
    popdef([VARIABLE])
])


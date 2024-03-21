UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    PRINTF = printf
else
    PRINTF = env printf
endif

HOST_ARCH = $(shell arch 2>/dev/null)

# Control the build verbosity
# 命令前加@表示关闭回显
ifeq ("$(VERBOSE)","1")
    Q :=
    VECHO = @true
    REDIR =
else
    Q := @
    VECHO = @$(PRINTF)
    REDIR = >/dev/null
endif

# Test suite
PASS_COLOR = \e[32;01m
NO_COLOR = \e[0m

pass = $(PRINTF) "$(PASS_COLOR)$1 Passed$(NO_COLOR)\n"

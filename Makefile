# ?=	条件变量赋值，如果变量未定义，则以?=右侧为其赋值
CC ?= gcc
# :=	简单扩展变量赋值，只扩展一次，避免递归
#开启以及优化，可执行文件生成调试信息
#	只支持 ANSI 标准的 C 语法，这一选项将禁止 GNU C 的某些特色，例如 asm 或 typeof 关键词；严格按照ISO（国际标准化组织）要求发出警告
#	生成所有警告信息；启用一些-Wall未启用的额外警告标志
#	不发出警告：局部变量被分配但未使用（除了其声明之外）
#	不发出警告：在 ISO C90 模式下使用可变参数宏，或者在 ISO C99 模式下使用 GNU 替代语法
#	不发出警告：未初始化的情况下使用具有自动或分配存储持续时间的对象
#	不发出警告：未指定参数类型的情况下声明或定义函数
#	不发出警告：在块中的语句之后发现声明
#	不发出警告：调用printf和scanf等函数时，参数不适合指定格式字符串的类型
#	不发出警告：调用printf和scanf等函数时，参数不适合指定格式字符串的类型的ISO（国际标准化组织）要求的警告
CFLAGS := -O -g \
	-ansi -pedantic \
	-Wall -Wextra \
	-Wno-unused-but-set-variable \
	-Wno-variadic-macros \
	-Wno-uninitialized \
	-Wno-strict-prototypes \
	-Wno-declaration-after-statement \
	-Wno-format \
	-Wno-format-pedantic

#立即?=延迟
#立即:=立即
#立即、延迟发生在GNU make的两个阶段，对变量和函数扩展的发生方式有直接影响，见官方文档

#用于配置和描述软件包的一些基本信息
include mk/common.mk
include mk/arm.mk
include mk/riscv.mk

#步骤
STAGE0 := shecc
STAGE1 := shecc-stage1.elf
STAGE2 := shecc-stage2.elf

OUT ?= out
ARCH ?= arm

#用shell命令find查找目录src并赋值给变量SRCDIR
#用shell命令find查找目录lib并赋值给变量LIBDIR
SRCDIR := $(shell find src -type d)
LIBDIR := $(shell find lib -type d)

#patsubst	$(patsubst  <pattern>,<replacement>,<text>)
#			返回被替换过后的字符串
#			形如$(OBJS:%.o=%.o.d)，这是patsubst的一种简写，见笔记
#wildcard	$(wildcard <PATTERN...>)
#			获取匹配该模式下的所有文件列表
SRCS := $(wildcard $(patsubst %,%/main.c, $(SRCDIR)))
OBJS := $(SRCS:%.c=$(OUT)/%.o)
deps := $(OBJS:%.o=%.o.d)
TESTS := $(wildcard tests/*.c)
TESTBINS := $(TESTS:%.c=$(OUT)/%.elf)
SNAPSHOTS := $(patsubst tests/%.c, tests/snapshots/%.json, $(TESTS))

#0
#	先决条件：1 11
#	配置文件、引导程序
all: config bootstrap

ifeq (,$(filter $(ARCH),arm riscv))
$(error Support ARM and RISC-V only. Select the target with "ARCH=arm" or "ARCH=riscv")
endif

ifneq ("$(wildcard $(PWD)/config)","")
#	即$(ARM_EXEC)的值，根据config配置文件的不同，可能是qemu-arm或者qemu-riscv32
TARGET_EXEC := $($(shell head -1 config | sed 's/.*: \([^ ]*\).*/\1/')_EXEC)
endif
export TARGET_EXEC

#1
#	ln -s src dst，建立软链接
#	调用函数在mk文件中定义，再将返回内容重定义到新创建的config文件
#	打印，打印函数在common.mk中定义
config:
	@echo "1" $@
	$(Q)ln -s $(PWD)/$(SRCDIR)/$(ARCH)-codegen.c $(SRCDIR)/codegen.c
	$(call $(ARCH)-specific-defs) > $@
	$(VECHO) "Target machine code switch to %s\n" $(ARCH)

#2
#
$(OUT)/tests/%.elf: tests/%.c $(OUT)/$(STAGE0)
	@echo "2" $@
	$(VECHO) "  SHECC\t$@\n"
	$(Q)$(OUT)/$(STAGE0) --dump-ir -o $@ $< > $(basename $@).log ; \
	chmod +x $@ ; $(PRINTF) "Running $@ ...\n"
	$(Q)$(TARGET_EXEC) $@ && $(call pass)

#3
check: $(TESTBINS) tests/driver.sh
	@echo "3" $@
	tests/driver.sh

#4
check-snapshots: $(OUT)/$(STAGE0) $(SNAPSHOTS) tests/check-snapshots.sh
	@echo "4" $@
	tests/check-snapshots.sh

#5
#	先决条件：7 ./src/main.c
#	打印
#	编译出目标文件，-c只编译生成目标文件
#	-MMD -MF out/src/main.o.d out/src/main.c
#	表示生成main.c的依赖关系文件main.o.d，$<指当前规则的第一个先决条件
$(OUT)/%.o: %.c

	@echo "5" $@
	$(VECHO) "  CC\t$@\n"
	$(Q)$(CC) -o $@ $(CFLAGS) -c -MMD -MF $@.d $<

SHELL_HACK := $(shell mkdir -p $(OUT) $(OUT)/$(SRCDIR) $(OUT)/tests)

#6
#	先决条件：7 ./lib/c.c
#	用内联器生成out/libc.inc
$(OUT)/libc.inc: $(OUT)/inliner $(LIBDIR)/c.c
	@echo "6" $@
	$(VECHO) "  GEN\t$@\n"
	$(Q)$(OUT)/inliner $(LIBDIR)/c.c $@

#7
#	先决条件：tools/inliner.c
#	编译和链接内联器，$@当前规则中的目标，$^当前规则中所有先决条件的列表
#	内联指将一些小的，常用的函数直接写在C文件中，而不是把它们放在库文件中。
#	这样做的好处是，可以减少函数调用的开销，因为不需要进行库的链接。
#	Inliner一般工作在IR层面，而不是像宏那样，在源码层面做替换
$(OUT)/inliner: tools/inliner.c
	@echo "7" $@
	$(VECHO) "  CC+LD\t$@\n"
	$(Q)$(CC) $(CFLAGS) -o $@ $^

#8
#	先决条件：6 5
#	用gcc把out/src/main.o链接成out/shecc
#	out/libc.inc在./src/main.c中include
$(OUT)/$(STAGE0): $(OUT)/libc.inc $(OBJS)
	@echo "8" $@
	$(VECHO) "  LD\t$@\n"
	$(Q)$(CC) $(OBJS) -o $@

#9
#	先决条件：8
#	用shecc把./src/main.c编译成out/shecc-stage1.elf，并生成IR
$(OUT)/$(STAGE1): $(OUT)/$(STAGE0)
	@echo "9" $@
	$(VECHO) "  SHECC\t$@\n"
	$(Q)$(OUT)/$(STAGE0) --dump-ir -o $@ $(SRCDIR)/main.c > $(OUT)/shecc-stage1.log
	$(Q)chmod a+x $@

#10
#	先决条件：9
#	/usr/bin/qemu-arm、out/shecc-stage1.elf
#	把./src/main.c编译成out/shecc-stage2.elf
$(OUT)/$(STAGE2): $(OUT)/$(STAGE1)
	@echo "10" $@
	$(VECHO) "  SHECC\t$@\n"
	$(Q)$(TARGET_EXEC) $(OUT)/$(STAGE1) -o $@ $(SRCDIR)/main.c

#11
#	先决条件：10
#	;为linux中的连续执行，不考虑指令前后的相关性
#	diff后的两个文件相同时返回true
#	比较./out/shecc-stage1.elf ./out/shecc-stage2.elf
#	false为shell命令的，设置退出码，当文件比对不相同时，Makefile退出
bootstrap: $(OUT)/$(STAGE2)
	@echo "11" $@
	$(Q)chmod 775 $(OUT)/$(STAGE2)
	$(Q)if ! diff -q $(OUT)/$(STAGE1) $(OUT)/$(STAGE2); then \
	echo "Unable to bootstrap. Aborting"; false; \
	fi

#伪目标，意思是这个目标本身不代表一个文件。
#执行这个目标不是为了得到某个文件或东西，而是单纯为了执行这个目标下面的命令。
#防止在Makefile中定义的只执行命令的目标和工作目录下的实际文件出现名字冲突
.PHONY: clean

#12
clean:
	@echo "12" $@
	-$(RM) $(OUT)/$(STAGE0) $(OUT)/$(STAGE1) $(OUT)/$(STAGE2)
	-$(RM) $(OBJS) $(deps)
	-$(RM) $(TESTBINS) $(OUT)/tests/*.log $(OUT)/tests/*.lst
	-$(RM) $(OUT)/shecc*.log
	-$(RM) $(OUT)/libc.inc

#13
distclean: clean
	@echo "13" $@
	-$(RM) $(OUT)/inliner $(OUT)/target $(SRCDIR)/codegen.c config

#“-”的意思是告诉make，忽略此操作的错误。make继续执行
-include $(deps)

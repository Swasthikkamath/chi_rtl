# Makefile for the CHI interconnect UVM testbench
#
# Two ways to build, for two different purposes:
#
#   make compile / make run   Xcelium. This is the sign-off path. It needs a
#                             licensed xrun on PATH.
#   make check                A static front end (slang). It parses, elaborates
#                             and type-checks the whole testbench against the
#                             real RTL, including UVM, with no licence. It
#                             cannot run a simulation, so it proves nothing
#                             about behaviour, but it catches every structural
#                             and typing error before an Xcelium seat is used.
#
# Both paths read the same chiFileList.f, so the two cannot diverge in what
# they compile. The RTL is never listed here: chiFileList.f refers to the
# design's own filelist.f, and CHI_RTL_ROOT says where that checkout is.
#
# Usage:
#   make run TEST=chiBaseTest SEED=1 VERBOSITY=UVM_MEDIUM
#   make run TEST=chiLinkBringUpTest WAVES=1
#   make regress
#
# Every knob below is overridable on the command line, and nothing about a
# particular test is hard-coded here.

CHI_TB_ROOT  ?= $(abspath $(CURDIR)/../..)
CHI_RTL_ROOT ?= $(abspath $(CHI_TB_ROOT)/../chi_rtl)
export CHI_TB_ROOT
export CHI_RTL_ROOT

TEST      ?= chiBaseTest
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM
TIMEOUT   ?= 500us
WAVES     ?= 0
SVA       ?= 1
COVERAGE  ?= 0

FILELIST  := $(CHI_TB_ROOT)/sim/xcelium/chiFileList.f
LOGDIR    := $(CURDIR)/logs
LOG       := $(LOGDIR)/$(TEST)_$(SEED).log

# ---------------------------------------------------------------------------
# The DUT file list
#
# The design owns which files make up the DUT, so that list is not copied
# here; it is derived from the design's own filelist.f every build. Three
# things have to be fixed on the way through, and all three are mechanical.
# See OPEN QUESTIONS Q21.
#
#   1. Its first line is a '#' comment. Argument files are not standardised on
#      the comment character, and xrun is not guaranteed to accept '#'. Every
#      such line is rewritten as '//'.
#   2. Its paths are relative to the design's root. They are made absolute so
#      that this list can be read from anywhere.
#   3. It pulls in rtl/top/*_compile.sv lint harnesses and rtl/sva/* bind
#      files. The harnesses are extra elaboration roots that -top hdlTop makes
#      dead weight, so they are always dropped. The binds attach assertions to
#      DUT internals; they are kept by default, because a firing one is worth
#      knowing about, and dropped by SVA=0.
#
# Set CHI_DUT_FILELIST on the command line to bypass all of this and supply an
# explicit list.
# ---------------------------------------------------------------------------

GENDIR           := $(CURDIR)/gen
DUT_FILELIST_SRC := $(CHI_RTL_ROOT)/filelist.f
CHI_DUT_FILELIST ?= $(GENDIR)/chiDutFileList_sva$(SVA).f
export CHI_DUT_FILELIST

# Configuration sweep. Any chi_cfg_t field the testbench exposes can be
# overridden from the command line as CFG_DEFINES="+define+CHI_TB_NUM_RNF=2".
CFG_DEFINES ?=

XRUN_COMMON := \
	-64bit \
	-sv \
	-uvm \
	-timescale 1ns/1ps \
	-top hdlTop \
	-top hvlTop \
	-f $(FILELIST) \
	$(CFG_DEFINES)

XRUN_ELAB := \
	-elaborate \
	-access +rwc \
	-nowarn RNDXCELON

XRUN_RUN := \
	+UVM_TESTNAME=$(TEST) \
	+UVM_VERBOSITY=$(VERBOSITY) \
	-svseed $(SEED) \
	+chiTimeout=$(TIMEOUT)

ifeq ($(WAVES),1)
XRUN_RUN += -input $(CHI_TB_ROOT)/sim/xcelium/probe.tcl
endif

# The design's filelist.f pulls in bind files that attach assertions to DUT
# internals. They are on by default because a firing one is worth knowing
# about, but a black-box debug session can switch them off without recompiling.
# See OPEN QUESTIONS Q21.
ifeq ($(SVA),0)
XRUN_RUN += +chiSvaOff
endif

ifeq ($(COVERAGE),1)
XRUN_COMMON += -coverage all -covoverwrite
endif

.PHONY: all compile run regress reseed testlist check check-sweep dutlist clean help

all: run

$(LOGDIR):
	@mkdir -p $(LOGDIR)

$(GENDIR):
	@mkdir -p $(GENDIR)

dutlist: $(CHI_DUT_FILELIST)

$(GENDIR)/chiDutFileList_sva$(SVA).f: $(DUT_FILELIST_SRC) $(MAKEFILE_LIST) | $(GENDIR)
	@test -f $(DUT_FILELIST_SRC) || \
		{ echo "no DUT file list at $(DUT_FILELIST_SRC); set CHI_RTL_ROOT"; exit 1; }
	@awk -v root='$(CHI_RTL_ROOT)' -v sva='$(SVA)' '\
		/^[[:space:]]*$$/ { print; next } \
		/^[[:space:]]*#/  { sub(/^[[:space:]]*#/, "//"); print; next } \
		/^[[:space:]]*\/\// { print; next } \
		/_compile\.sv[[:space:]]*$$/ { print "// dropped, lint harness: " $$0; next } \
		/\/sva\// { if (sva == "0") { print "// dropped by SVA=0: " $$0; next } } \
		{ print root "/" $$0 }' $(DUT_FILELIST_SRC) > $@
	@echo "dutlist: $@"

compile: $(CHI_DUT_FILELIST) | $(LOGDIR)
	xrun $(XRUN_COMMON) $(XRUN_ELAB) -l $(LOGDIR)/compile.log

run: $(CHI_DUT_FILELIST) | $(LOGDIR)
	xrun $(XRUN_COMMON) $(XRUN_RUN) -l $(LOG)

# ---------------------------------------------------------------------------
# Licence-free static elaboration
#
# SLANG points at a binary that understands -F command files; UVM_HOME at an
# Accellera UVM source tree. Both default to the tooling directory at the top
# of this repository, which is not checked in, so `make check` reports what is
# missing rather than failing obscurely.
# ---------------------------------------------------------------------------

SLANG    ?= $(abspath $(CHI_TB_ROOT)/../tools)/slang
UVM_HOME ?= $(abspath $(CHI_TB_ROOT)/../tools)/uvm-core-2020.3.1

# -Wport-width-* is the whole point of the flat signal ports on the BFMs. A
# port connection resizes silently in SystemVerilog, so without these two a
# BFM flit port that disagreed with the chi_if bus would compile clean and
# corrupt every flit. With them, chiGlobalsPkg's flit widths are checked
# against the DUT's own buses at compile time, for whatever configuration is
# being swept. Neither one may be demoted to a warning we tolerate.
SLANG_ARGS := \
	--std 1800-2017 \
	--single-unit \
	--relax-enum-conversions \
	--timescale 1ns/1ps \
	-Wport-width-trunc \
	-Wport-width-expand \
	-I $(UVM_HOME)/src \
	$(UVM_HOME)/src/uvm_pkg.sv \
	-F $(FILELIST) \
	--top hdlTop \
	--top hvlTop \
	$(CFG_DEFINES)

check: $(CHI_DUT_FILELIST)
	@test -x $(SLANG) || { echo "no static front end at $(SLANG); set SLANG="; exit 1; }
	@test -d $(UVM_HOME)/src || { echo "no UVM source at $(UVM_HOME); set UVM_HOME="; exit 1; }
	@$(SLANG) $(SLANG_ARGS) > $(CURDIR)/check.log 2>&1; \
		status=$$?; cat $(CURDIR)/check.log; test $$status -eq 0
	@if grep -q "port connection" $(CURDIR)/check.log; then \
		echo "check: a port connection was resized; the flit model disagrees with the DUT bus"; \
		exit 1; \
	fi

# Sweeps the configuration and re-checks elaboration at each point, which is
# what proves the flit widths are formulas rather than constants fitted to one
# configuration.
CHECK_SWEEP ?= \
	"" \
	"+define+CHI_TB_DATA_W=128" \
	"+define+CHI_TB_DATA_W=512" \
	"+define+CHI_TB_NODEID_W=13 +define+CHI_TB_ADDR_W=40" \
	"+define+CHI_TB_RSVDC_W=8 +define+CHI_TB_PBHA_EN=1" \
	"+define+CHI_TB_MPAM_EN=1 +define+CHI_TB_MEC_EN=1 +define+CHI_TB_CDA_EN=1" \
	"+define+CHI_TB_DATA_CHECK_EN=0 +define+CHI_TB_POISON_EN=0" \
	"+define+CHI_TB_PARITY_EN=1" \
	"+define+CHI_TB_NUM_RNF=2 +define+CHI_TB_NUM_SNF=1 +define+CHI_TB_NUM_HNF=2"

check-sweep:
	@for cfg in $(CHECK_SWEEP); do \
		echo "=== $$cfg"; \
		$(MAKE) --no-print-directory check CFG_DEFINES="$$cfg" > /dev/null || \
			{ echo "FAILED: $$cfg"; exit 1; }; \
	done
	@echo "check-sweep: every configuration elaborates"

# ---------------------------------------------------------------------------
# Regression
#
# The list of tests is not written here. It is derived from chiTestPkg.sv,
# which is the file that has to name every test anyway, so a test that
# compiles is a test the regression runs. Anything ending in Test is one;
# the virtual sequence and the base class's helpers are not.
#
# xrun's exit status does not follow UVM_ERROR, so the log is read for the
# report summary. A run that produced no summary at all is a failure too:
# that is what a compile error or a timeout looks like here.
# ---------------------------------------------------------------------------

TESTPKG  := $(CHI_TB_ROOT)/src/hvlTop/test/chiTestPkg.sv
TESTLIST := $(GENDIR)/chiTestList.f
SEEDS    ?= 1 2 3

$(TESTLIST): $(TESTPKG) | $(GENDIR)
	@sed -n 's/^[[:space:]]*`include[[:space:]]*"\(chi[A-Za-z0-9_]*Test\)\.sv".*/\1/p' \
		$(TESTPKG) > $@
	@echo "testlist: $$(wc -l < $@) tests from $(notdir $(TESTPKG))"

testlist: $(TESTLIST)
	@cat $(TESTLIST)

regress: $(TESTLIST) $(CHI_DUT_FILELIST) | $(LOGDIR)
	@fail=0; pass=0; \
	for test in $$(cat $(TESTLIST)); do \
		for seed in $(SEEDS); do \
			log=$(LOGDIR)/$${test}_$${seed}.log; \
			$(MAKE) --no-print-directory run TEST=$$test SEED=$$seed > /dev/null 2>&1; \
			if $(CHI_TB_ROOT)/sim/xcelium/chiVerdict.sh $$log; then \
				pass=$$((pass+1)); \
			else \
				fail=$$((fail+1)); \
				echo "FAIL $$test seed $$seed  $$log"; \
			fi; \
		done; \
	done; \
	echo "regress: $$pass passed, $$fail failed"; \
	test $$fail -eq 0

# One test over the seeds, for when a regression failure is being chased.
reseed: $(CHI_DUT_FILELIST) | $(LOGDIR)
	@for seed in $(SEEDS); do \
		$(MAKE) run TEST=$(TEST) SEED=$$seed || exit 1; \
	done

clean:
	rm -rf xcelium.d INCA_libs waves.shm cov_work $(GENDIR) $(LOGDIR) *.log *.history check.log

help:
	@echo "make compile              elaborate with Xcelium"
	@echo "make run TEST=<name>      run one test"
	@echo "make check                elaborate with the licence-free front end"
	@echo "make check-sweep          re-elaborate over the configuration sweep"
	@echo "make regress              run every test in chiTestPkg over SEEDS"
	@echo "make reseed TEST=<name>   run one test over SEEDS"
	@echo "make testlist             print the tests the regression will run"
	@echo "make dutlist              regenerate the sanitised DUT file list"
	@echo ""
	@echo "knobs: SEED SEEDS VERBOSITY TIMEOUT WAVES=1 SVA=0 COVERAGE=1"
	@echo "       CFG_DEFINES='+define+CHI_TB_NUM_RNF=2 +define+CHI_TB_DATA_W=512'"
	@echo "       SVA=0 drops the DUT assertion binds from the compile"
	@echo "       CHI_DUT_FILELIST=<path> supplies an explicit DUT file list"

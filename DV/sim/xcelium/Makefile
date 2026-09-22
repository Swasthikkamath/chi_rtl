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

.PHONY: all compile run regress check check-sweep clean help

all: run

$(LOGDIR):
	@mkdir -p $(LOGDIR)

compile: | $(LOGDIR)
	xrun $(XRUN_COMMON) $(XRUN_ELAB) -l $(LOGDIR)/compile.log

run: | $(LOGDIR)
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
	$(CFG_DEFINES)

check:
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

regress: | $(LOGDIR)
	@for seed in 1 2 3; do \
		$(MAKE) run TEST=$(TEST) SEED=$$seed || exit 1; \
	done

clean:
	rm -rf xcelium.d INCA_libs waves.shm cov_work $(LOGDIR) *.log *.history check.log

help:
	@echo "make compile              elaborate with Xcelium"
	@echo "make run TEST=<name>      run one test"
	@echo "make check                elaborate with the licence-free front end"
	@echo "make regress TEST=<name>  run one test over three seeds"
	@echo ""
	@echo "knobs: SEED VERBOSITY TIMEOUT WAVES=1 SVA=0 COVERAGE=1"
	@echo "       CFG_DEFINES='+define+CHI_TB_NUM_RNF=2 +define+CHI_TB_DATA_W=512'"

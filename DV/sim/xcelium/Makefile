# Xcelium flow for the CHI interconnect testbench.
# compile elaborates hdlTop only. run, regress, and waves gain hvlTop
# when the UVM tests are added. Logs are parsed for UVM_ERROR and
# UVM_FATAL; a zero exit status is not a pass.
#
# chiFileList.f is read with -F. Paths inside it, including the
# referenced chi_rtl/filelist.f, resolve from the file that names them.
# [ASSUMPTION:21]

XRUN ?= xrun
FILELIST := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))chiFileList.f
TEST ?= chiLinkBringUpTest
SEED ?= 1
VERBOSITY ?= UVM_MEDIUM
RUN_OPTS = -sv -uvm -access +rwc -F $(FILELIST) +UVM_TESTNAME=$(TEST) \
	+UVM_VERBOSITY=$(VERBOSITY) -svseed $(SEED)

.PHONY: compile run regress waves clean

compile:
	$(XRUN) -sv -uvm -elaborate -access +rwc -top hdlTop -F $(FILELIST)

run:
	$(XRUN) $(RUN_OPTS) -top hdlTop -top hvlTop -l simv.log
	@python3 -c 'import pathlib,sys; t=pathlib.Path("simv.log").read_text(errors="replace"); \
e=t.count("UVM_ERROR"); f=t.count("UVM_FATAL"); \
sys.exit(0 if e==0 and f==0 else 1)'

regress:
	$(MAKE) run TEST=$(TEST) SEED=$(SEED) VERBOSITY=$(VERBOSITY)

waves:
	$(XRUN) $(RUN_OPTS) -top hdlTop -top hvlTop -input probe.tcl -l simv.log

clean:
	rm -rf xcelium.d waves.shm *.log xrun.history xrun.key *.shm

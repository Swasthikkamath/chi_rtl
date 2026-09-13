# CHI UVM testbench, Xcelium flow.
#
# Run from this directory so that xrun leaves its scratch here rather than in
# the project root.
#
#   make compile                 elaborate only
#   make TEST=chiSharedLineTest  compile and run one test
#   make regress                 run every test
#   make waves TEST=...          run with an SHM probe, report the database
#   make clean

TEST      ?= chiCoherentTrafficTest
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM
ACCESS    ?= +rwc

XRUN      := xrun
XRUN_ARGS := -sv -uvm -access $(ACCESS) -top hdlTop -top hvlTop -f chiFileList.f

TESTS := chiLinkBringUpTest \
         chiCoherentTrafficTest \
         chiSharedLineTest \
         chiRetryStressTest \
         chiPassiveAgentTest

.PHONY: compile run regress waves clean

compile:
	$(XRUN) $(XRUN_ARGS) -elaborate -l elab.log

run:
	$(XRUN) $(XRUN_ARGS) \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) \
	  -svseed $(SEED) -l run_$(TEST).log

# A regression is only green when every test reports zero errors and zero
# fatals, so the summary lines are checked rather than the exit status.
regress:
	@rc=0; \
	for t in $(TESTS); do \
	  $(XRUN) $(XRUN_ARGS) +UVM_TESTNAME=$$t -svseed $(SEED) \
	    -l run_$$t.log > /dev/null 2>&1; \
	  e=$$(sed -n 's/^UVM_ERROR : *//p' run_$$t.log); \
	  f=$$(sed -n 's/^UVM_FATAL : *//p' run_$$t.log); \
	  if [ "$$e" = "0" ] && [ "$$f" = "0" ]; then s=PASS; else s=FAIL; rc=1; fi; \
	  printf '%-26s %s (errors %s, fatals %s)\n' "$$t" "$$s" "$$e" "$$f"; \
	done; \
	exit $$rc

# simvision needs a display, so dump instead of launching a viewer and report
# where the database landed.
waves:
	$(XRUN) $(XRUN_ARGS) +UVM_TESTNAME=$(TEST) -svseed $(SEED) \
	  -input probe.tcl -l run_$(TEST).log
	@echo "waveform database: $(CURDIR)/waves.shm"

clean:
	rm -rf xcelium.d INCA_libs worklib waves.shm *.log *.history *.key

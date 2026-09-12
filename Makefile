VERILATOR ?= verilator
PANDOC    ?= pandoc

LINT_FLAGS = --lint-only --assert --sv -Wall -Wno-fatal \
             -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN \
             -Wno-BLKLOOPINIT -f filelist.f

# Tops that live in filelist.f.
LINT_TOPS  = chi_interconnect_compile chi_sva_compile chi_hnf_compile \
             chi_link_compile

# Supplemental harnesses that are appended to the compile set on demand.
EXTRA_TOPS = chi_mesh_compile chi_ring_compile chi_xbar_compile \
             chi_sam_compile chi_stage1_compile

SIM_FLAGS = --binary --assert --sv -Wno-fatal \
            -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN \
            -Wno-BLKLOOPINIT -f filelist.f

SIM_TB  = tb/chi_smoke_tb.sv
SIM_BIN = obj_dir/chi_smoke

DOC_SRC = doc-src/chi_interconnect_design_spec.md
DOC_OUT = docs/chi_interconnect_design_spec.docx

.PHONY: all lint sim doc clean

all: lint sim doc

lint:
	@for top in $(LINT_TOPS); do \
	  echo "== $$top =="; \
	  $(VERILATOR) $(LINT_FLAGS) --top-module $$top || exit 1; \
	done
	@for top in $(EXTRA_TOPS); do \
	  echo "== $$top =="; \
	  $(VERILATOR) $(LINT_FLAGS) top/$$top.sv --top-module $$top || exit 1; \
	done

# The smoke run is what executes the elaboration self-checks in
# chi_interconnect_top, so it catches configuration and NodeID-encoding
# mistakes that a lint-only pass cannot see.
sim: $(SIM_BIN)
	$(SIM_BIN)

$(SIM_BIN): $(SIM_TB) filelist.f
	$(VERILATOR) $(SIM_FLAGS) $(SIM_TB) --top-module chi_smoke_tb -o chi_smoke

doc: $(DOC_OUT)

$(DOC_OUT): $(DOC_SRC)
	@mkdir -p docs
	$(PANDOC) $(DOC_SRC) --toc --toc-depth=2 -o $@

clean:
	rm -rf obj_dir

VERILATOR ?= verilator
XRUN      ?= xrun
PANDOC    ?= pandoc

LINT_FLAGS = --lint-only --assert --sv -Wall -Wno-fatal \
             -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN \
             -Wno-BLKLOOPINIT -f filelist.f

# Tops that live in filelist.f.
LINT_TOPS  = chi_interconnect_compile chi_sva_compile chi_hnf_compile \
             chi_link_compile

# Supplemental harnesses that are appended to the compile set on demand.
EXTRA_TOPS = chi_mesh_compile chi_ring_compile chi_xbar_compile \
             chi_sam_compile chi_stage1_compile chi_cookbook_compile

SIM_FLAGS = --binary --assert --sv -Wno-fatal \
            -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNDRIVEN \
            -Wno-BLKLOOPINIT -f filelist.f

SIM_SRC = tb/chi_node_link_bfm.sv tb/chi_sim_harness.sv tb/chi_smoke_tb.sv
SIM_BIN = obj_dir/chi_smoke

DOT       ?= dot
PYTHON    ?= python3
DOC_SRC    = doc-src/chi_interconnect_design_spec.md
DOC_OUT    = docs/chi_interconnect_design_spec.docx
DOC_REF    = doc-src/reference.docx
DOC_FILTER = doc-src/house_style.lua
# Applied to the Word file after pandoc: the cover art behind the title page,
# and the bullet glyphs, which a reference document cannot carry.
DOC_FINISH = doc-src/finish_docx.py
DOC_COVER  = doc-src/cover.png
FIG_DIR    = doc-src/figures
FIG_DOT    = $(wildcard $(FIG_DIR)/*.dot)
FIG_PNG    = $(FIG_DOT:.dot=.png)

# Verilator initialises state to zero, which hides anything that depends on a
# register or an input having been driven. Re-running with randomised
# initialisation approximates the X-propagation a four-state simulator gives
# for free, and is the only way this flow catches a missing driver.
SIM_SEEDS = 1 2 7 42 1234

.PHONY: all lint xcelium sim simrand doc figures clean

all: lint sim simrand doc

lint:
	@for top in $(LINT_TOPS); do \
	  echo "== $$top =="; \
	  $(VERILATOR) $(LINT_FLAGS) --top-module $$top || exit 1; \
	done
	@for top in $(EXTRA_TOPS); do \
	  echo "== $$top =="; \
	  $(VERILATOR) $(LINT_FLAGS) rtl/top/$$top.sv --top-module $$top || exit 1; \
	done

# The smoke run is what executes the elaboration self-checks in
# chi_interconnect_top, so it catches configuration and NodeID-encoding
# mistakes that a lint-only pass cannot see.
# Elaboration of every lint top with Cadence Xcelium, each in its own work
# directory so one top's snapshot does not replace another's.
xcelium:
	@for top in $(LINT_TOPS); do \
	  echo "== $$top =="; \
	  $(XRUN) -sv -elaborate -xmlibdirname xcelium.d/$$top \
	    -f filelist.f -top $$top || exit 1; \
	done
	@for top in $(EXTRA_TOPS); do \
	  echo "== $$top =="; \
	  $(XRUN) -sv -elaborate -xmlibdirname xcelium.d/$$top \
	    -f filelist.f rtl/top/$$top.sv -top $$top || exit 1; \
	done

sim: $(SIM_BIN)
	$(SIM_BIN)

simrand: $(SIM_BIN)
	@for seed in $(SIM_SEEDS); do \
	  echo "== randomised init, seed $$seed =="; \
	  $(SIM_BIN) +verilator+rand+reset+2 +verilator+seed+$$seed || exit 1; \
	done

$(SIM_BIN): $(SIM_SRC) filelist.f
	$(VERILATOR) $(SIM_FLAGS) $(SIM_SRC) --top-module chi_smoke_tb -o chi_smoke

doc: $(DOC_OUT)

# Figures are generated from Graphviz sources so the diagrams cannot drift out
# of review: the .dot files are the reviewable artifact, the .png files are
# build output that happens to be committed so the document builds without
# Graphviz installed.
figures: $(FIG_PNG)

$(FIG_DIR)/%.png: $(FIG_DIR)/%.dot
	$(DOT) -Tpng -Gdpi=150 -o $@ $<

# The Word template carries the house style of the document series: page
# geometry, fonts, table rules, caption placement and the footer. It is built
# from a script so the styles are reviewable as text rather than as a binary.
$(DOC_REF): doc-src/build_reference_docx.py
	$(PYTHON) doc-src/build_reference_docx.py $@

$(DOC_OUT): $(DOC_SRC) $(FIG_PNG) $(DOC_REF) $(DOC_FILTER) $(DOC_FINISH) $(DOC_COVER)
	@mkdir -p docs
	$(PANDOC) $(DOC_SRC) --toc --toc-depth=2 \
	  --lua-filter=$(DOC_FILTER) --reference-doc=$(DOC_REF) \
	  --resource-path=doc-src -o $@
	$(PYTHON) $(DOC_FINISH) $@ $(DOC_COVER)

clean:
	rm -rf obj_dir xcelium.d xrun.history xrun.log

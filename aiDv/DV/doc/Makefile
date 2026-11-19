# Document build for the verification specification.
#
# The root Makefile builds the design specification with pandoc. Pandoc is not
# available on this machine, so this flow renders the same Markdown subset to
# HTML and converts it with LibreOffice instead. The Markdown is the reviewable
# artifact; the PDF is build output that happens to be committed so the
# document is readable without a LibreOffice install.

PYTHON ?= python3

DOC_SRC = chi_dv_specification.md
DOC_OUT = chi_dv_specification.pdf
BUILDER = build_pdf.py

.PHONY: pdf clean

pdf: $(DOC_OUT)

$(DOC_OUT): $(DOC_SRC) $(BUILDER)
	$(PYTHON) $(BUILDER) $(DOC_SRC) $@

clean:
	rm -f $(DOC_OUT)

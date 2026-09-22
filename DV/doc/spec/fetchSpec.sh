#!/usr/bin/env bash
#
# Fetches the AMBA CHI Architecture Specification, ARM IHI 0050 Issue H, into
# this directory, and renders it to text beside the PDF.
#
# The document is Arm copyright. It is free to download and non-confidential,
# but it is not ours to redistribute, so the PDF is not committed: this script
# is committed instead, so that anyone can reproduce the exact input the flit
# model and the [SPEC:IHI0050H ...] citations were checked against.
#
# The static link below is the one Arm's documentation service currently
# advertises for the latest issue. If it stops resolving, query the service
# for the current one:
#
#   curl -sSL https://documentation-service.arm.com/documentation/ihi0050/latest/ \
#     | python3 -c 'import json,sys; print(json.load(sys.stdin)["_links"]["resources"][0]["href"])'
#
# Usage: DV/doc/spec/fetchSpec.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pdf="${here}/IHI0050H_amba_chi_architecture_spec.pdf"
txt="${here}/IHI0050H_amba_chi_architecture_spec.txt"
url="https://documentation-service.arm.com/static/69df590612ab715369d31af4?token="

if [[ ! -f "${pdf}" ]]; then
  echo "fetchSpec: downloading IHI 0050 Issue H"
  curl -fsSL -o "${pdf}" "${url}"
fi

file "${pdf}" | grep -q 'PDF document' || {
  echo "fetchSpec: ${pdf} is not a PDF; the download link has probably moved" >&2
  exit 1
}

python3 - "${pdf}" "${txt}" <<'PY'
import sys

try:
    import pypdf
except ImportError:
    sys.exit("fetchSpec: pip install pypdf to render the text copy")

reader = pypdf.PdfReader(sys.argv[1])
with open(sys.argv[2], "w") as out:
    for number, page in enumerate(reader.pages, start=1):
        out.write("\n=== PAGE %d ===\n" % number)
        out.write(page.extract_text() or "")
print("fetchSpec: %d pages rendered to %s" % (len(reader.pages), sys.argv[2]))
PY

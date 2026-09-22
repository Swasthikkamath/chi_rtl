#!/usr/bin/env bash
#
# Reads one xrun log and decides whether the test passed.
#
# xrun's exit status reports whether the simulator ran, not whether the test
# passed, so a run full of UVM_ERROR exits 0. The verdict has to come from the
# UVM report summary instead. Three things count as a failure and the third is
# the one that catches the worst case:
#
#   1. a non-zero UVM_ERROR or UVM_FATAL count
#   2. an xrun error line, which is a compile or elaboration failure
#   3. no report summary at all
#
# The third matters because a test that hung until the timeout, or died before
# run_test, leaves a log with no errors in it. Treating that as a pass would
# make the quietest failure the easiest one to miss.

set -u

log=${1:-}

if [[ -z ${log} || ! -f ${log} ]]; then
  echo "chiVerdict: no log at '${log}'" >&2
  exit 1
fi

if grep -qE '^(xmelab|xmvlog|xmsim|xrun): \*E' "${log}"; then
  echo "chiVerdict: tool error in ${log}" >&2
  exit 1
fi

# The summary line looks like "UVM_ERROR :    0". Anything else means the
# summary was never printed.
summary=$(grep -cE '^UVM_(INFO|WARNING|ERROR|FATAL)[[:space:]]*:' "${log}" || true)
if [[ ${summary} -eq 0 ]]; then
  echo "chiVerdict: no UVM report summary in ${log}; the run did not finish" >&2
  exit 1
fi

for severity in UVM_ERROR UVM_FATAL; do
  count=$(sed -nE "s/^${severity}[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "${log}" | tail -1)
  if [[ -z ${count} ]]; then
    echo "chiVerdict: no ${severity} count in ${log}" >&2
    exit 1
  fi
  if [[ ${count} -ne 0 ]]; then
    echo "chiVerdict: ${count} ${severity} in ${log}" >&2
    exit 1
  fi
done

exit 0

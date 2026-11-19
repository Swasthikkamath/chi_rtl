# Open questions

Points where the spec, the configuration document and the DUT do not line up,
or where Stage 1 took a decision that a later stage should revisit. Each one is
marked `See OPEN QUESTIONS` at the corresponding place in the source.

## 1. TXSACTIVE is driven by the fabric, not by the node

`[SPEC:IHI0050H B14.4]` makes TXSACTIVE an output of the transmitting node, so
each agent BFM would own its own. In this DUT `rtl/link/chi_link_port.sv` drives
both TXSACTIVE and RXSACTIVE on every port, so the BFM cannot drive TXSACTIVE
without creating a second driver. The BFM therefore leaves both alone and only
observes them.

*Impact:* an agent cannot signal activity independently of the fabric, so a
test cannot hold a link awake while the fabric believes it is idle.
*Decision needed:* whether the DUT should hand TXSACTIVE back to the node.

Referenced in `DV/src/hdlTop/chiLink/chiLinkLayerBfm.svh`.

## 2. Channels that exist at the link layer but carry no protocol traffic

A Subordinate is given a receive RSP channel and an RN-I a receive SNP channel.
Neither is reachable in the protocol: `[SPEC:IHI0050H A2.1 Table A2-1]` shows
no protocol RSP arriving at a Subordinate, and an I/O coherent Requester is
never snooped. Both channels nevertheless have to be credited or link
activation never completes.

Stage 1 credits them and treats any real flit on them as a finding rather than
dropping it silently.

*Decision needed:* confirm that crediting an unused channel is the intended
behaviour rather than an artefact of a generic port.

Referenced in `DV/src/globals/chiGlobalsPkg.sv`,
`DV/src/hdlTop/chiSubordinateAgentBfm/chiSubordinateDriverBfm.sv` and
`DV/src/hvlTop/chiEnv/chiSubordinate/chiSubordinateDriverProxy.sv`.

## 3. Node counts cannot be raised without a placement table

`defaultMeshPlacement` enumerates ordinals 0 to 13 only, and the ordinal of
every node after a resized class shifts. Raising `numRnf` or `numRnd` past the
default silently invalidates the placement table rather than failing to
elaborate.

Stage 1 keeps the DUT's default counts. A test that wants a different shape has
to supply `PLACEMENTS` explicitly.

*Decision needed:* whether the DUT should compute placements from the counts,
or at least assert when it cannot.

Referenced in `DV/src/globals/chiGlobalsPkg.sv`.

## 4. RetToSrc is set on every snoop of a read's burst

Writes no longer ask for data, but for a read the Home still sets RetToSrc on
all snoops it sends, so every sharer returns the line and all but the first
copy is discarded. This is wasteful rather than incorrect, and only because all
copies of a line hold the same bytes: a Shared Dirty holder differs from a
Shared Clean one only in who owes the writeback. The Home relies on that when
it keeps the first line it is given and drops the rest, so it does not look at
which response carried PassDirty when choosing whose data to forward.

*Decision needed:* whether the Home should set RetToSrc on one snoop only, and
if so how it should recover dirty data from a peer it did not ask.

## 5. DMT, DWT and DCT are disabled

`[CFGDOC:#6.4]` permits all three. Stage 1 switches them off in
`chiGlobalsPkg` so the Home stays in the data path and the scoreboard sees
every beat. Enabling them changes who sources CompData and who the DBID comes
from, and needs its own scoreboard work.

## 6. The subordinate model answers every read from memory

The Subordinate BFM is a plain memory: it has no notion of exclusives, no
error injection beyond what a sequence asks for, and no ordering beyond
first-come-first-served. Tests that need a Subordinate that reorders or that
returns `NDERR` will need the model extended.

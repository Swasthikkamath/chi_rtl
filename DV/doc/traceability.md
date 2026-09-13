# Traceability

Every configurable quantity in the testbench is derived, never guessed. This
table records where each one comes from. `[SPEC:...]` cites AMBA 5 CHI
IHI 0050H; `[CFGDOC:...]` cites `doc-src/chi_interconnect_design_spec.md`;
`[RTL:...]` cites the DUT source that the testbench must agree with bit for
bit.

## Fabric shape

| Quantity | Testbench symbol | Source |
| --- | --- | --- |
| Requester count | `CHI_NUM_REQUESTERS` | `[RTL:pkg/chi_cfg_pkg.sv CHI_CFG.numRnf/numRni/numRnd]` |
| Subordinate count | `CHI_NUM_SUBORDINATES` | `[RTL:pkg/chi_cfg_pkg.sv CHI_CFG.numSnf/numSni]` |
| Home node count | `CHI_NUM_HNF` | `[RTL:pkg/chi_cfg_pkg.sv CHI_CFG.numHnf]` |
| Node class per port | `chiRequesterAgentConfig.nodeClass` | `[CFGDOC:#3.1]`, `[RTL:top/chi_fabric_top.sv generate blocks]` |
| NodeID per port | `chiNodeIdOf()` | `[RTL:pkg/chi_cfg_pkg.sv RNF_NODE_IDS/SN_NODE_IDS]`, encoding `[SPEC:IHI0050H A2.3]` |
| Address map | `chiHomeForAddress()` | `[RTL:sam/chi_sam.sv]`, `[CFGDOC:#5.2]` |

## Link layer

| Quantity | Testbench symbol | Source |
| --- | --- | --- |
| L-Credit depth | `CHI_CFG.lcrdDepth` | `[RTL:pkg/chi_cfg_pkg.sv]`, semantics `[SPEC:IHI0050H B13.3]` |
| Link states | `chiLinkStateE` | `[RTL:link/chi_link_fsm.sv]`, `[SPEC:IHI0050H B13.4]` |
| Activation handshake | `chiLinkLayerBfm` TX/RX FSMs | `[SPEC:IHI0050H B13.4.2]` |
| SYSCOREQ/SYSCOACK | `chiRequesterDriverProxy::bringUp` | `[SPEC:IHI0050H B13.5]` |
| Channels present per class | `channelApplies()` | `[SPEC:IHI0050H A2.1 Table A2-1]` |

## Flit formats

| Quantity | Testbench symbol | Source |
| --- | --- | --- |
| REQ/RSP/SNP/DAT field layout | `chi_pkg::pack*Flit/unpack*Flit` (reused) | `[RTL:pkg/chi_pkg.sv]`, `[SPEC:IHI0050H B13.6-B13.9]` |
| Configured flit widths | `REQ_FLIT_W` etc. | `[RTL:pkg/chi_pkg.sv reqFlitWidth()]` |
| Architectural maximum widths | `CHI_MAX_*_FLIT_W` | `[RTL:pkg/chi_pkg.sv]`, `[SPEC:IHI0050H B13.6]` |
| Widest flit for the monitor | `CHI_WIDEST_FLIT_W` | max of the four architectural maxima, because `chi_if` carries the packed maximum, not the configured width |
| Resp encoding (state + PassDirty) | `chi_resp_e` | `[SPEC:IHI0050H B13.10.34]` |
| Cache states | `chi_cache_state_e` | `[SPEC:IHI0050H B2.2]` |

## Protocol behaviour modelled

| Behaviour | Testbench component | Source |
| --- | --- | --- |
| RetryAck / PCrdGrant / credited re-send | `chiRequesterDriverProxy::issueWithRetry` | `[SPEC:IHI0050H B2.10]` |
| TxnID uniqueness per source | `chiRequesterDriverProxy` TxnID pool, `topScoreboard` reuse check | `[SPEC:IHI0050H B2.3.1]` |
| DBID matching for write data | `chiSubordinateDriverProxy::serveWrite`, `topScoreboard.dbidOwner` | `[SPEC:IHI0050H B2.9.1]` |
| CompAck ordering | `chiRequesterDriverProxy::sendCompAck` | `[SPEC:IHI0050H B2.8]` |
| Snoop response states | `chiRequesterCacheModel::applySnoop` | `[SPEC:IHI0050H B4.9, Table B4-9]` |
| Unique ownership invariant | `topScoreboard::checkUniqueOwnership` | `[SPEC:IHI0050H B2.2]` |
| Data integrity against memory | `topScoreboard::checkReadData` + `chiSubordinateMemoryModel` | `[SPEC:IHI0050H B2.12]` |

## Stage 1 scope

DMT, DWT and DCT are switched off in `chiGlobalsPkg` for this stage, so the
Home always sits in the data path. `[CFGDOC:#6.4]` allows them; enabling them
is future work recorded in `open-questions.md`.

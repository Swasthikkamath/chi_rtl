# Traceability

Two tables and then the encodings. The first says where each finding is
demonstrated, the second where each specification rule the testbench
enforces is enforced. The feature-to-test matrix is §4 of the DV
specification and is not repeated here.

## Findings to evidence

Every row names the thing that would fail if the finding were wrong, not
the thing that describes it. A finding whose evidence is a waiver says so.

| ID | Kind | What demonstrates it |
| --- | --- | --- |
| F-1 | DUT, parity polarity | `chiParityTest` drives spec-odd parity and expects `linkParityError`. Needs `parityEn=1`; the default configuration cannot show it |
| F-2 | DUT, TXSACTIVE ownership | Waiver. `topLinkModel` checks `RXSACTIVE` only, and the testbench never drives `TXSACTIVE`. `chiLinkBringUpTest` is where it would surface |
| F-3 | DUT, one-directional `linkUp` | `topLinkModel` compares `linkUp` against TX RUN alone. `chiLinkBringUpTest` fails if that correspondence breaks |
| F-4 | DUT, `multiReqEn` unused | `chiMultiReqTest` reports SKIP and drives nothing. The requester driver pins MultiReq to 0 |
| F-5 | DUT, SnpDVMOp to RN-I | `chiDvmTest` with `allowRniDvmSnoop` 1 counts a warning per occurrence; setting it to 0 turns each into an error |
| F-6 | DUT, missing DVM DBIDResp phase | `chiDvmTest` with `expectDvmDbidResp` 0 tolerates and counts; setting it to 1 makes the absent phase an error |
| F-7 | DUT, `unmappedError` unconnected | `chiAddrIsDeliverable` is checked in `hdlTop` at time 0 against both stimulus windows. `chiUnmappedTest` reports SKIP rather than hanging |
| F-8 | DUT, `numMn = 0` indexes out of range | `hdlTop` rejects the configuration at elaboration by name. The raw failure is the `slang` run recorded in the iteration log |
| F-9 | DUT, `mpamW` sizes nothing | The boundary width sweep in `make check-sweep`. `chiMpamTest` exercises the field; it is not a width test |
| F-10 | TB, flit fields missing | Closed. `hdlTop` fails elaboration if any channel's named fields stop summing to its bus width |
| F-11 | DUT, drives node-side `*CHK` | Waiver. The testbench leaves them alone; the multi-bit `TX<x>FLITCHK` it does drive carries the parity test |
| F-12 | TB, five wrong Subordinate flows | Closed. Each flow now cites the figure it came from, and the Subordinate reports any request outside the permitted Home-to-Subordinate set |
| F-13 | TB, PrefetchTgt unimplemented | Closed. `chiPrefetchTest` fails if the hint reaches no SN-F, and the read after it would not complete if the driver still waited |
| F-14 | TB, AllowRetry randomised | Closed. Constrained to 1 on a first send; the Subordinate's credit check is what would have reported it |
| F-15 | TB, response-shape coverage lied | Closed. The flag comes from the response opcode, and `chiRespShapeTest` fails if no separate pair was driven |

## Specification rules the testbench enforces

Each of these is a rule the DUT could break without breaking anything
else, so each has a check rather than only a covergroup.

| Rule | Citation | Where it is checked |
| --- | --- | --- |
| A line is Unique at one node or Shared at many, never both | B2.2, B4.8 | `topDirectoryModel.chiCheckInvariant` |
| Taking a line Unique requires every other holder to have been snooped | B4.8 | `topDirectoryModel.chiAcquire` |
| A snoop response must answer a snoop that was sent | B2.4 | `topDirectoryModel.chiApplyResp` |
| An ordered read returns ReadReceipt before data and before Comp | B2.7.5 | `topLifecycleModel.chiNoteRsp`, `chiNoteDat` |
| Every transaction retires; none is outstanding at end of test | B2.3 | `topLifecycleModel.chiCheckEnd` |
| An error completion reaches the transaction it belongs to | B9.4 | `topLifecycleModel.rnErrByLine`, `chiDataErrTest` |
| Read data is the last value written, wherever it came from | B2.3 | `topMemoryModel.chiRnCheckRead`, proven live by `chiDataCorruptTest` |
| A flit is sent only against a credit, and only in RUN | B14.2 | `topLinkModel` |
| PrefetchTgt carries TxnID 0 and gets no response | B4.2.6.2, B2.4.2 | `topLifecycleModel.chiNoteReq`, `chiSubordinateDriverProxy`, `chiPrefetchTest` |
| AllowRetry is 1 on a first send, 0 only against a granted P-Credit | B2.10.2.1 | `chiRequesterTx` constraint; `chiSubordinateDriverProxy.chiConsumeCredit` |
| A Home sends a Subordinate only the requests Tables B4.2/B4.3 permit | B4.2 | `chiSubordinateDriverProxy.chiIsLegalHere` |

## Encodings

Opcodes, responses, link states, and PAS encodings are defined once, in
`chiGlobalsPkg`. Widths are formulas in that package (`REQ_FLIT_W`,
`RSP_FLIT_W`, `SNP_FLIT_W`, `DAT_FLIT_W`, and the field offsets). They are
not copied here. Each row is the encoding the testbench drives and
checks. [SPEC:IHI0050H B13.8] [SPEC:IHI0050H B4.8] [SPEC:IHI0050H B13.5]
[SPEC:IHI0050H B13.10.68]

## REQ opcodes

| Name | Encoding |
| --- | --- |
| REQ_LCRD_RETURN | 7'h00 |
| REQ_READ_SHARED | 7'h01 |
| REQ_READ_CLEAN | 7'h02 |
| REQ_READ_ONCE | 7'h03 |
| REQ_READ_NO_SNP | 7'h04 |
| REQ_P_CRD_RETURN | 7'h05 |
| REQ_READ_UNIQUE | 7'h07 |
| REQ_CLEAN_SHARED | 7'h08 |
| REQ_CLEAN_INVALID | 7'h09 |
| REQ_MAKE_INVALID | 7'h0A |
| REQ_CLEAN_UNIQUE | 7'h0B |
| REQ_MAKE_UNIQUE | 7'h0C |
| REQ_EVICT | 7'h0D |
| REQ_CLEAN_INVALID_STORAGE | 7'h0E |
| REQ_READ_NO_SNP_SEP | 7'h11 |
| REQ_CLEAN_SHARED_PERSIST_SEP | 7'h13 |
| REQ_DVM_OP | 7'h14 |
| REQ_WRITE_EVICT_FULL | 7'h15 |
| REQ_WRITE_CLEAN_FULL | 7'h17 |
| REQ_WRITE_UNIQUE_PTL | 7'h18 |
| REQ_WRITE_UNIQUE_FULL | 7'h19 |
| REQ_WRITE_BACK_PTL | 7'h1A |
| REQ_WRITE_BACK_FULL | 7'h1B |
| REQ_WRITE_NO_SNP_PTL | 7'h1C |
| REQ_WRITE_NO_SNP_FULL | 7'h1D |
| REQ_WRITE_UNIQUE_FULL_STASH | 7'h20 |
| REQ_WRITE_UNIQUE_PTL_STASH | 7'h21 |
| REQ_STASH_ONCE_SHARED | 7'h22 |
| REQ_STASH_ONCE_UNIQUE | 7'h23 |
| REQ_READ_ONCE_CLEAN_INVALID | 7'h24 |
| REQ_READ_ONCE_MAKE_INVALID | 7'h25 |
| REQ_READ_NOT_SHARED_DIRTY | 7'h26 |
| REQ_CLEAN_SHARED_PERSIST | 7'h27 |
| REQ_ATOMIC_STORE_ADD | 7'h28 |
| REQ_ATOMIC_STORE_CLR | 7'h29 |
| REQ_ATOMIC_STORE_EOR | 7'h2A |
| REQ_ATOMIC_STORE_SET | 7'h2B |
| REQ_ATOMIC_STORE_SMAX | 7'h2C |
| REQ_ATOMIC_STORE_SMIN | 7'h2D |
| REQ_ATOMIC_STORE_UMAX | 7'h2E |
| REQ_ATOMIC_STORE_UMIN | 7'h2F |
| REQ_ATOMIC_LOAD_ADD | 7'h30 |
| REQ_ATOMIC_LOAD_CLR | 7'h31 |
| REQ_ATOMIC_LOAD_EOR | 7'h32 |
| REQ_ATOMIC_LOAD_SET | 7'h33 |
| REQ_ATOMIC_LOAD_SMAX | 7'h34 |
| REQ_ATOMIC_LOAD_SMIN | 7'h35 |
| REQ_ATOMIC_LOAD_UMAX | 7'h36 |
| REQ_ATOMIC_LOAD_UMIN | 7'h37 |
| REQ_ATOMIC_SWAP | 7'h38 |
| REQ_ATOMIC_COMPARE | 7'h39 |
| REQ_PREFETCH_TGT | 7'h3A |
| REQ_MAKE_READ_UNIQUE | 7'h41 |
| REQ_WRITE_EVICT_OR_EVICT | 7'h42 |
| REQ_WRITE_UNIQUE_ZERO | 7'h43 |
| REQ_WRITE_NO_SNP_ZERO | 7'h44 |
| REQ_STASH_ONCE_SEP_SHARED | 7'h47 |
| REQ_STASH_ONCE_SEP_UNIQUE | 7'h48 |
| REQ_READ_PREFER_UNIQUE | 7'h4C |
| REQ_CLEAN_INVALID_POPA | 7'h4D |
| REQ_WRITE_NO_SNP_DEF | 7'h4E |
| REQ_WRITE_NO_SNP_FULL_CLEAN_SH | 7'h50 |
| REQ_WRITE_NO_SNP_FULL_CLEAN_INV | 7'h51 |
| REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP | 7'h52 |
| REQ_WRITE_UNIQUE_FULL_CLEAN_SH | 7'h54 |
| REQ_WRITE_UNIQUE_FULL_CLEAN_SH_PER_SEP | 7'h56 |
| REQ_WRITE_UNIQUE_FULL_CLEAN_INV_STRG | 7'h57 |
| REQ_WRITE_BACK_FULL_CLEAN_SH | 7'h58 |
| REQ_WRITE_BACK_FULL_CLEAN_INV | 7'h59 |
| REQ_WRITE_BACK_FULL_CLEAN_SH_PER_SEP | 7'h5A |
| REQ_WRITE_BACK_FULL_CLEAN_INV_STRG | 7'h5B |
| REQ_WRITE_CLEAN_FULL_CLEAN_SH | 7'h5C |
| REQ_WRITE_CLEAN_FULL_CLEAN_SH_PER_SEP | 7'h5E |
| REQ_WRITE_NO_SNP_PTL_CLEAN_SH | 7'h60 |
| REQ_WRITE_NO_SNP_PTL_CLEAN_INV | 7'h61 |
| REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP | 7'h62 |
| REQ_WRITE_UNIQUE_PTL_CLEAN_SH | 7'h64 |
| REQ_WRITE_UNIQUE_PTL_CLEAN_SH_PER_SEP | 7'h66 |
| REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA | 7'h70 |
| REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA | 7'h71 |
| REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG | 7'h72 |
| REQ_WRITE_BACK_FULL_CLEAN_INV_POPA | 7'h79 |

## RSP opcodes

| Name | Encoding |
| --- | --- |
| RSP_LCRD_RETURN | 5'h00 |
| RSP_SNP_RESP | 5'h01 |
| RSP_COMP_ACK | 5'h02 |
| RSP_RETRY_ACK | 5'h03 |
| RSP_COMP | 5'h04 |
| RSP_COMP_DBID_RESP | 5'h05 |
| RSP_DBID_RESP | 5'h06 |
| RSP_P_CRD_GRANT | 5'h07 |
| RSP_READ_RECEIPT | 5'h08 |
| RSP_SNP_RESP_FWDED | 5'h09 |
| RSP_TAG_MATCH | 5'h0A |
| RSP_RESP_SEP_DATA | 5'h0B |
| RSP_PERSIST | 5'h0C |
| RSP_COMP_PERSIST | 5'h0D |
| RSP_DBID_RESP_ORD | 5'h0E |
| RSP_STASH_DONE | 5'h10 |
| RSP_COMP_STASH_DONE | 5'h11 |
| RSP_COMP_CMO | 5'h14 |

## SNP opcodes

| Name | Encoding |
| --- | --- |
| SNP_LCRD_RETURN | 5'h00 |
| SNP_SHARED | 5'h01 |
| SNP_CLEAN | 5'h02 |
| SNP_ONCE | 5'h03 |
| SNP_NOT_SHARED_DIRTY | 5'h04 |
| SNP_UNIQUE_STASH | 5'h05 |
| SNP_MAKE_INVALID_STASH | 5'h06 |
| SNP_UNIQUE | 5'h07 |
| SNP_CLEAN_SHARED | 5'h08 |
| SNP_CLEAN_INVALID | 5'h09 |
| SNP_MAKE_INVALID | 5'h0A |
| SNP_STASH_UNIQUE | 5'h0B |
| SNP_STASH_SHARED | 5'h0C |
| SNP_DVM_OP | 5'h0D |
| SNP_QUERY | 5'h10 |
| SNP_SHARED_FWD | 5'h11 |
| SNP_CLEAN_FWD | 5'h12 |
| SNP_ONCE_FWD | 5'h13 |
| SNP_NOT_SHARED_DIRTY_FWD | 5'h14 |
| SNP_PREFER_UNIQUE | 5'h15 |
| SNP_PREFER_UNIQUE_FWD | 5'h16 |
| SNP_UNIQUE_FWD | 5'h17 |

## DAT opcodes

| Name | Encoding |
| --- | --- |
| DAT_LCRD_RETURN | 4'h0 |
| DAT_SNP_RESP_DATA | 4'h1 |
| DAT_COPY_BACK_WR_DATA | 4'h2 |
| DAT_NON_COPY_BACK_WR_DATA | 4'h3 |
| DAT_COMP_DATA | 4'h4 |
| DAT_SNP_RESP_DATA_PTL | 4'h5 |
| DAT_SNP_RESP_DATA_FWDED | 4'h6 |
| DAT_WRITE_DATA_CANCEL | 4'h7 |
| DAT_DATA_SEP_RESP | 4'hB |
| DAT_NCB_WR_DATA_COMP_ACK | 4'hC |

## Resp

UC and UD share 3'b010. The cache model decides which one applies.

| Name | Encoding |
| --- | --- |
| RESP_I | 3'b000 |
| RESP_SC | 3'b001 |
| RESP_UC_UD | 3'b010 |
| RESP_SD | 3'b011 |
| RESP_I_PD | 3'b100 |
| RESP_SC_PD | 3'b101 |
| RESP_UC_PD | 3'b110 |
| RESP_SD_PD | 3'b111 |

## RespErr

| Name | Encoding |
| --- | --- |
| RESP_ERR_OK | 2'b00 |
| RESP_ERR_EXOK | 2'b01 |
| RESP_ERR_DERR | 2'b10 |
| RESP_ERR_NDERR | 2'b11 |

## Link state

| Name | Encoding |
| --- | --- |
| LINK_STOP | 2'd0 |
| LINK_ACTIVATE | 2'd1 |
| LINK_RUN | 2'd2 |
| LINK_DEACTIVATE | 2'd3 |

## PAS

| Name | Encoding |
| --- | --- |
| PAS_SECURE | 3'b000 |
| PAS_NON_SECURE | 3'b001 |
| PAS_ROOT | 3'b010 |
| PAS_REALM | 3'b011 |
| PAS_SYSTEM_AGENT | 3'b100 |
| PAS_NON_SECURE_PROTECTED | 3'b101 |

Stimulus uses `PAS_NON_SECURE`. `pasIsSecure` is what `chiSamLookup` consults.

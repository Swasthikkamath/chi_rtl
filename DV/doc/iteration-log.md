# Bring-up iteration log

Each entry is a failure observed in simulation, what it turned out to be, and
the change that fixed it. Failures are split into testbench bugs and DUT bugs;
the DUT fixes are all in `rtl/hnf/` and each carries a comment at the change site.

## Compile and elaborate

1. `chiNodeClassT` alias worked as an argument type but not as a return type in
   Xcelium. Dropped the alias and used `chi_node_class_e` directly.
2. Multiple drivers on `always_ff` outputs in `chiLinkLayerBfm.svh` and
   `chiMonitorBfm.sv`: declaration initialisers on signals that the reset
   branch also assigns. Removed the initialisers.
3. Adjacent string literals in `$sformatf` are not concatenated in
   SystemVerilog. Wrapped every multi-line format string in `{}`.
4. `chiEnvPkg` could not open `chiEnvConfig.sv`: the `chiEnv` directory itself
   was missing from the include path in `chiFileList.f`.
5. `try_next_item` is a task, so `chiSubordinateDriverProxy::currentPolicy`
   could not be a function. Converted it to a task with an output argument.

## Testbench bugs found by simulation

6. **L-Credit overflow reported on every channel.** `chiMonitorBfm` was
   counting credits granted since reset rather than credits currently held.
   Changed to a balance: granted minus spent.
7. **X addresses on RSP and DAT flits.** Those channels carry no address, but
   the monitor was copying the field anyway. Added `addrValid` to
   `chiRequesterTx`, and the scoreboard and coverage now resolve the address
   from a `(agent, TxnID)` table populated when the request is seen.
8. **`CHI_WIDEST_FLIT_W` too narrow.** It was derived from this
   configuration's DAT width, but `chi_if` carries the architectural maximum,
   so the monitor's part-select ran off the end of the payload and pulled in X.
   Now the maximum of the four architectural maxima.
9. **Requester driver deadlocked on accepted reads.** `issueWithRetry` waited
   for a RetryAck on RSP, but an accepted ReadShared answers with CompData on
   DAT and nothing ever arrives on RSP. It now watches both mailboxes and
   treats either as the answer.
10. **Subordinate completed writes before the data arrived.** `serveWrite` sent
    a combined CompDBIDResp up front. Split into DBIDResp, then wait for the
    data, then Comp; the DBID is the request's TxnID and the write-data mailbox
    is keyed by `(SrcID, TxnID)`.
11. **Read data and snoop response data reassembled in the same buffer.** The
    scoreboard keyed its beat accumulator on `(agent, TxnID)` alone, but a
    Requester's own TxnID space and the TxnID space of snoops sent to it are
    independent and collide. A ReadUnique's CompData and a concurrent
    SnpRespData with the same TxnID were merged, so the read never completed
    and its data check compared the wrong bytes. The key now includes the
    direction and the peer node, because two Home Nodes may use the same TxnID
    towards one Requester. The same widening was needed for the snoop record
    and the DBID record.

12. **Two transactions in flight to the same line.** The dispatcher checked
    `isOutstanding` and then let the read and write paths mark the line, with a
    TxnID allocation and a capacity eviction in between. Two access threads
    both found the line free and both went to the fabric. When the first was
    retried the second overtook it, so a Requester that had meanwhile acquired
    and dirtied the line still had a read outstanding on it; the Home saw the
    requester as the only sharer, snooped nobody, and returned stale memory.
    The claim is now taken in the same step as the check.

13. **The line claim was released by a bystander.** `allocate()` reset the
    in-flight mark and `invalidate()` deleted it, so installing a line at
    completion cleared the claim of the transaction that was still running, and
    a snoop invalidating an unrelated line's neighbour cleared whatever claim
    it found. Residency and the in-flight mark are now independent: only the
    driver thread that took the claim releases it.

14. **A store landed in the middle of a snoop.** The snoop handler read the
    line out, sent the data beats over several cycles, and only then applied
    the new state. A silent store to the same line in that window left the
    snoop carrying pre-store bytes while this Requester kept post-store bytes,
    and the peer given that data diverged. A real cache locks the line for the
    duration of the snoop, so stores and snoop processing now take a common
    lock.

## DUT bugs found by simulation

All are in the HN-F. Each fix is small and commented in place.

15. **POS entries leaked** (`rtl/hnf/chi_pos.sv`). `freeValid` and `progressValid`
    are handled in the same `always_ff`, and the progress branch wrote
    `POS_ALLOCATED` over the `POS_FREE` that the free branch had just written
    when both targeted the same index. Entries were never reclaimed, the
    hazard logic then held `reqInReady` low and the fabric deadlocked. The
    progress branch now stands down when a free lands on the same index.

16. **Write data delivered to the wrong Requester** (`chi_hnf_top.sv`). The
    data router chose between "towards memory" and "towards the Requester" by
    comparing the flit's SrcID against the active request's SrcID. A Requester
    only sends its write data after the DBID reaches it, by which time the Home
    may be serving someone else, so write data was handed to an unrelated
    Requester as its read data. Routing is now by data opcode
    (`isWriteData()`).

17. **Snoop responses carrying data deadlocked the Home.** In `HNF_SNOOP_WAIT`
    the Home only consumed `SnpRespData` for atomics, and the snoop generator's
    `responseValid` was wired only to RSP-channel snoop responses. A snoop sent
    with RetToSrc therefore never retired. The Home now accepts data-channel
    snoop responses, and `responseSource` is taken from whichever channel
    carried the answer so the generator credits the right node.

18. **Reads were granted Unique while peers still held the line.** The Home
    forwarded the Subordinate's CompData unchanged, and a Subordinate knows
    nothing about coherence. `grantedReadResp()` now replaces the Resp field
    with the state the directory justifies: Unique only when no other Requester
    holds a copy, and Invalid for ReadOnce so a non-caching Requester is never
    recorded as a holder.

19. **Requests asking for Unique snooped with SnpShared.** The snoop opcode was
    chosen as "SnpUnique if this is a write, else SnpShared", so a ReadUnique
    never invalidated its peers. `snoopForRequest()` now maps each request to
    the snoop that makes its target state reachable.

20. **The Requester was snooped for its own transaction.** The sharer set was
    taken straight from the snoop filter. A CleanUnique from a current sharer
    therefore invalidated the very copy it was asking to upgrade. The requester
    is now masked out of the snoop set.

21. **Dataless requests were sent downstream.** CleanUnique, MakeUnique and the
    CMOs fell through to the memory-read path and then waited for a CompAck
    that the Requester had no reason to send, which wedged the Home and starved
    every retry record behind it. Added `HNF_DATALESS_COMP`, which answers with
    a bare Comp and updates the directory.

22. **ReadOnce was never snooped.** It is not a coherent request, so it skipped
    the snoop phase and read stale memory whenever a peer held the line dirty.
    `isSnoopable()` separates "must be snooped" from "changes the directory".

23. **CompData overtook the remaining snoops.** Once the Home began forwarding
    snoop-supplied data it passed the first `SnpRespData` straight through,
    while peers later in the snoop burst had not yet been invalidated. Since
    CompData carries the completion, the Requester was granted Unique before
    the other copies were gone. The Home now buffers the returned line
    (`snoopDatBuf`) and replays it as CompData from `HNF_SNOOP_DATA_SEND` only
    after the snoop burst finishes.

24. **Dirty data recovered by a dataless request was dropped.** A CleanUnique
    or CMO that snooped a dirty peer received the line with PassDirty set and
    then answered with a bare Comp, so the only dirty copy in the system was
    discarded and memory kept the old contents. Added the writeback sequence
    `HNF_SNOOP_WB_REQ` / `HNF_SNOOP_WB_DATA` / `HNF_SNOOP_WB_COMP`, which
    pushes the buffered line to the Subordinate as WriteNoSnpFull before the
    request completes.

25. **WriteUnique asked its peers for data it would discard.** The snoop was
    SnpUnique with RetToSrc set for every snoopable write, including full-line
    writes that overwrite the whole line. Full writes now snoop with
    SnpMakeInvalid, only WriteUniquePtl needs SnpUnique, and RetToSrc is off
    for writes.

## Final state

All five tests run clean, and a 120-run sweep of the three traffic tests over
40 seeds reports no errors:

| Test | UVM_ERROR | UVM_FATAL |
| --- | --- | --- |
| `chiLinkBringUpTest` | 0 | 0 |
| `chiCoherentTrafficTest` | 0 | 0 |
| `chiSharedLineTest` | 0 | 0 |
| `chiRetryStressTest` | 0 | 0 |
| `chiPassiveAgentTest` | 0 | 0 |

`chiCoherentTrafficTest` at seed 7 exercises 118 requests, 70 completions, 48
retries with 48 matching grants, 39 snoops and 58 checked read-data
comparisons, with 3 comparisons skipped for a concurrent write.

`chi_dv_specification.md` is the specification of the environment those runs
exercise.

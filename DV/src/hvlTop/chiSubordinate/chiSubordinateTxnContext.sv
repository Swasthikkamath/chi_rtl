// State for one request the Subordinate has accepted but not yet finished.
// A write lives here from the moment its DBID is handed out until the last
// data packet has been folded into memory.

class chiSubordinateTxnContext;
  chiReqFlitT req;
  chiTxnIdT dbId;

  // Data collection. beatsExpected starts at the count implied by Size and
  // is revised downward if a packet says the sender elided the rest.
  // See OPEN QUESTIONS Q8. [SPEC:IHI0050H B13.10.58 NumDat]
  int unsigned beatsExpected;
  int unsigned beatsSeen;
  bit cancelled;

  // Packets are folded into memory as they arrive rather than buffered,
  // because arrival order is not guaranteed and the byte offset comes from
  // DataID, so there is nothing to reassemble in order.
  logic [511:0] gathered;

  // Set once the collection thread has nothing left to wait for.
  mailbox #(int) ping;

  function new();
    beatsExpected = 0;
    beatsSeen = 0;
    cancelled = 1'b0;
    gathered = '0;
    ping = new();
  endfunction

  function bit chiDataComplete();
    return cancelled || (beatsSeen >= beatsExpected);
  endfunction
endclass

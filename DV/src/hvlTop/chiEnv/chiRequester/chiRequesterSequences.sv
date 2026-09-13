// Requester sequence library.
//
// Sequences express intent only: an access kind and an address. They never
// name an opcode, because the opcode that realises an intent depends on cache
// state that the driver holds and the sequence does not. This is what keeps
// one sequence library usable by a fully coherent and an I/O coherent
// Requester alike.

class chiRequesterBaseSeq extends uvm_sequence #(chiRequesterTx);

  chiRequesterSequencer localSequencer;

  // Number of accesses to generate.
  rand int unsigned accessCount;

  // Address window. A small window is what makes two Requesters contend for
  // the same line, which is the only way snoops are generated at all.
  chiAddrT addrBase  = 'h0000_1000;
  chiAddrT addrRange = 'h0000_1000;

  constraint reasonableCount {
    accessCount inside {[1:64]};
  }

  `uvm_object_utils(chiRequesterBaseSeq)

  function new(string name = "chiRequesterBaseSeq");
    super.new(name);
    accessCount = 8;
  endfunction

  task pre_start();
    if (!$cast(localSequencer, m_sequencer))
      `uvm_fatal(get_type_name(), "sequencer is not a chiRequesterSequencer")
  endtask

  // One access at a line-aligned address inside the window.
  protected task doAccess(chiAccessKindE kind, chiAddrT addr);
    chiRequesterTx item;
    item = chiRequesterTx::type_id::create("item");
    start_item(item);
    if (!item.randomize() with {
          accessKind == kind;
          addr       == local::addr;
        })
      `uvm_error(get_type_name(), "randomization failed")
    finish_item(item);
  endtask

  protected function chiAddrT randomLineAddr();
    chiAddrT offset;
    offset = chiAddrT'($urandom_range(0, (addrRange / CHI_LINE_BYTES) - 1))
             * CHI_LINE_BYTES;
    return lineBaseOf(addrBase + offset);
  endfunction
endclass

// Reads only. On a fully coherent Requester the first read of a line fetches
// it and every later read of the same line is a cache hit that never reaches
// the fabric, which is itself worth exercising.
class chiRequesterReadSeq extends chiRequesterBaseSeq;
  `uvm_object_utils(chiRequesterReadSeq)

  function new(string name = "chiRequesterReadSeq");
    super.new(name);
  endfunction

  task body();
    for (int unsigned i = 0; i < accessCount; i++)
      doAccess(CHI_ACCESS_READ, randomLineAddr());
  endtask
endclass

// Writes only. On a fully coherent Requester this drives the line to unique
// and dirty, which is what makes a later snoop from another Requester have to
// move data rather than just change state.
class chiRequesterWriteSeq extends chiRequesterBaseSeq;
  `uvm_object_utils(chiRequesterWriteSeq)

  function new(string name = "chiRequesterWriteSeq");
    super.new(name);
  endfunction

  task body();
    for (int unsigned i = 0; i < accessCount; i++)
      doAccess(CHI_ACCESS_WRITE, randomLineAddr());
  endtask
endclass

// A mix, which is the default traffic pattern. The read to write ratio is
// weighted towards reads because a read that hits generates no traffic, and an
// all-write stream would keep every line unique and so never produce a shared
// state.
class chiRequesterRandomSeq extends chiRequesterBaseSeq;
  rand int unsigned writePercent;

  constraint writeMix {
    writePercent inside {[20:50]};
  }

  `uvm_object_utils(chiRequesterRandomSeq)

  function new(string name = "chiRequesterRandomSeq");
    super.new(name);
    writePercent = 35;
  endfunction

  task body();
    for (int unsigned i = 0; i < accessCount; i++) begin
      if ($urandom_range(0, 99) < writePercent)
        doAccess(CHI_ACCESS_WRITE, randomLineAddr());
      else
        doAccess(CHI_ACCESS_READ, randomLineAddr());
    end
  endtask
endclass

// Deliberate contention: every Requester running this hits the same handful of
// lines, so the Home Node has to snoop and the snoop filter has to track
// multiple sharers. Without something like this a run can pass without ever
// generating a snoop.
class chiRequesterSharedLineSeq extends chiRequesterBaseSeq;
  `uvm_object_utils(chiRequesterSharedLineSeq)

  function new(string name = "chiRequesterSharedLineSeq");
    super.new(name);
    addrRange = 4 * CHI_LINE_BYTES;
  endfunction

  task body();
    for (int unsigned i = 0; i < accessCount; i++) begin
      // Mostly reads so several Requesters hold the line shared at once, with
      // an occasional write to invalidate them all.
      if ((i % 4) == 3)
        doAccess(CHI_ACCESS_WRITE, randomLineAddr());
      else
        doAccess(CHI_ACCESS_READ, randomLineAddr());
    end
  endtask
endclass

// Back-to-back accesses with no gaps, to fill the Home Node's transaction pool
// and provoke RetryAck. The driver's outstanding limit is what actually
// decides how hard this pushes [SPEC:IHI0050H B2.10].
class chiRequesterRetryStressSeq extends chiRequesterBaseSeq;
  `uvm_object_utils(chiRequesterRetryStressSeq)

  function new(string name = "chiRequesterRetryStressSeq");
    super.new(name);
    accessCount = 48;
    // A wide window so accesses spread over Home Nodes rather than serialising
    // on one line's hazard logic.
    addrRange   = 'h0001_0000;
  endfunction

  task body();
    for (int unsigned i = 0; i < accessCount; i++)
      doAccess(((i % 3) == 0) ? CHI_ACCESS_WRITE : CHI_ACCESS_READ,
               randomLineAddr());
  endtask
endclass

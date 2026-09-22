// One directed intent on the sequencer this sequence is started on.

class chiOneIntentSeq extends chiRequesterSeq;
  chiRequesterIntentE intent;
  chiAddrT addr;
  logic [SIZE_W-1:0] size;
  logic [ORDER_W-1:0] order;

  `uvm_object_utils(chiOneIntentSeq)

  function new(string name = "chiOneIntentSeq");
    super.new(name);
    intent = CHI_INTENT_READ_NO_SNP;
    addr = '0;
    size = SIZE_W'(6);
    order = '0;
  endfunction

  task body();
    chiSendIntent(intent, addr, size, order, 1'b1);
  endtask
endclass

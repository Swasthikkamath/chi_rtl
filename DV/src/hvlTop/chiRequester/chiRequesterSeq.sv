// Base sequence. Tests extend it and call chiSendIntent. finish_item
// returns once the driver has accepted the item; get_response waits
// until the completion thread has applied the response to the cache model.

class chiRequesterSeq extends uvm_sequence#(chiRequesterTx);
  `uvm_object_utils(chiRequesterSeq)
  `uvm_declare_p_sequencer(chiRequesterSequencer)

  function new(string name = "chiRequesterSeq");
    super.new(name);
  endfunction

  task body();
  endtask

  task chiSendIntent(
    input chiRequesterIntentE intent,
    input chiAddrT addr,
    input logic [SIZE_W-1:0] size = SIZE_W'(6)
  );
    chiRequesterTx item;
    chiRequesterTx rsp;
    item = chiRequesterTx::type_id::create("item");
    start_item(item);
    item.nodeClass = p_sequencer.cfg.nodeClass;
    // Pin the directed fields, then randomize the rest. Turning rand_mode
    // off keeps the values and still checks them against chiLegalIntent.
    item.intent = intent;
    item.addr = addr;
    item.size = size;
    item.intent.rand_mode(0);
    item.addr.rand_mode(0);
    item.size.rand_mode(0);
    if (!item.randomize())
      `uvm_fatal("chiRequesterSeq", "intent randomize failed")
    finish_item(item);
    get_response(rsp);
  endtask
endclass

// Base sequence. Tests call chiEnableRetry or chiSetRespErr. With no
// sequence the driver never retries and answers RESP_ERR_OK.

class chiSubordinateSeq extends uvm_sequence#(chiSubordinateTx);
  `uvm_object_utils(chiSubordinateSeq)
  `uvm_declare_p_sequencer(chiSubordinateSequencer)

  function new(string name = "chiSubordinateSeq");
    super.new(name);
  endfunction

  task body();
  endtask

  task chiEnableRetry(input bit enable);
    chiSubordinateTx item;
    if (p_sequencer.cfg == null)
      `uvm_fatal("chiSubordinateSeq", "sequencer cfg is null")
    item = chiSubordinateTx::type_id::create("item");
    start_item(item);
    item.enableRetry = enable;
    item.injectRespErr = p_sequencer.cfg.injectRespErr;
    finish_item(item);
  endtask

  task chiSetRespErr(input chiRespErrE respErr);
    chiSubordinateTx item;
    if (p_sequencer.cfg == null)
      `uvm_fatal("chiSubordinateSeq", "sequencer cfg is null")
    item = chiSubordinateTx::type_id::create("item");
    start_item(item);
    item.enableRetry = p_sequencer.cfg.enableRetry;
    item.injectRespErr = respErr;
    finish_item(item);
  endtask
endclass

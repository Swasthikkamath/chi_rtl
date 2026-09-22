// Sets the standing response error for requests no other rule matches.
// The driver keeps reading cfg.defaultRespErr after this sequence ends.

class chiSubordinateRespErrSeq extends chiSubordinateSeq;
  chiRespErrE respErr;

  `uvm_object_utils(chiSubordinateRespErrSeq)

  function new(string name = "chiSubordinateRespErrSeq");
    super.new(name);
    respErr = RESP_ERR_NDERR;
  endfunction

  task body();
    if (p_sequencer.cfg == null)
      `uvm_fatal("chiSubordinateRespErrSeq", "sequencer cfg is null")
    p_sequencer.cfg.defaultRespErr = respErr;
  endtask
endclass

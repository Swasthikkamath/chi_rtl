// Base sequence plus the handful of response policies that tests actually
// need. Each one installs rules and returns; the driver applies them as
// requests arrive, so a sequence that ends does not end the policy. Rules
// with a use count retire themselves.

class chiSubordinateSeq extends uvm_sequence#(chiSubordinateTx);
  `uvm_object_utils(chiSubordinateSeq)
  `uvm_declare_p_sequencer(chiSubordinateSequencer)

  function new(string name = "chiSubordinateSeq");
    super.new(name);
  endfunction

  task body();
  endtask

  task chiInstallRule(input chiSubordinateTx rule);
    start_item(rule);
    finish_item(rule);
  endtask

  // Answer everything normally. Installing nothing would do the same, but
  // an explicit default makes a test that forgot to pick a policy look the
  // same as one that chose this.
  task chiAnswerNormally();
    chiSubordinateTx rule;
    rule = chiSubordinateTx::type_id::create("rule");
    start_item(rule);
    if (!rule.randomize() with {
      matchKind == CHI_SN_MATCH_ALL;
      respErr == RESP_ERR_OK;
      useCount == 0;
      extraDelay == 0;
      corruptReadData == 1'b0;
    })
      `uvm_fatal("chiSubordinateSeq", "default rule randomize failed")
    finish_item(rule);
  endtask
endclass

// Return a data error on one line. The line is the parameter because the
// interesting check is that the error reaches the requester that asked for
// that line and no other.
// [SPEC:IHI0050H B9.4 Error response]
class chiSubordinateErrorSeq extends chiSubordinateSeq;
  chiAddrT errorLine;
  chiRespErrE errorKind;
  int unsigned errorCount;

  `uvm_object_utils(chiSubordinateErrorSeq)

  function new(string name = "chiSubordinateErrorSeq");
    super.new(name);
    errorLine = '0;
    errorKind = RESP_ERR_DERR;
    errorCount = 1;
  endfunction

  task body();
    chiSubordinateTx rule;
    rule = chiSubordinateTx::type_id::create("rule");
    start_item(rule);
    if (!rule.randomize() with {
      matchKind == CHI_SN_MATCH_ADDR;
      matchAddr == errorLine;
      respErr == errorKind;
      useCount == errorCount;
      extraDelay == 0;
    })
      `uvm_fatal("chiSubordinateErrorSeq", "error rule randomize failed")
    finish_item(rule);
  endtask
endclass

// Corrupt read data while still reporting RespErr OK. This is the case an
// end-to-end data check has to catch on its own, so it is the sequence that
// proves the scoreboard's data comparison is real and not vacuous.
class chiSubordinateCorruptSeq extends chiSubordinateSeq;
  chiAddrT corruptLine;

  `uvm_object_utils(chiSubordinateCorruptSeq)

  function new(string name = "chiSubordinateCorruptSeq");
    super.new(name);
    corruptLine = '0;
  endfunction

  task body();
    chiSubordinateTx rule;
    rule = chiSubordinateTx::type_id::create("rule");
    start_item(rule);
    if (!rule.randomize() with {
      matchKind == CHI_SN_MATCH_ADDR;
      matchAddr == corruptLine;
      respErr == RESP_ERR_OK;
      corruptReadData == 1'b1;
      useCount == 1;
    })
      `uvm_fatal("chiSubordinateCorruptSeq", "corrupt rule randomize failed")
    finish_item(rule);
  endtask
endclass

// Answer slowly. A Subordinate that takes its time is the only way to make
// the interconnect run out of its own resources, so this is what fills the
// DUT's buffers and provokes RetryAck upstream.
class chiSubordinateSlowSeq extends chiSubordinateSeq;
  int unsigned slowBy;

  `uvm_object_utils(chiSubordinateSlowSeq)

  function new(string name = "chiSubordinateSlowSeq");
    super.new(name);
    slowBy = 24;
  endfunction

  task body();
    chiSubordinateTx rule;
    rule = chiSubordinateTx::type_id::create("rule");
    start_item(rule);
    if (!rule.randomize() with {
      matchKind == CHI_SN_MATCH_ALL;
      respErr == RESP_ERR_OK;
      useCount == 0;
      extraDelay == slowBy;
    })
      `uvm_fatal("chiSubordinateSlowSeq", "slow rule randomize failed")
    finish_item(rule);
  endtask
endclass

// Refuse retryable requests so the DUT has to go round the RetryAck and
// PCrdGrant loop. Driven from the config rather than a rule because retry
// is decided before the request is even classified.
// [SPEC:IHI0050H B2.12 Transaction retry]
class chiSubordinateRetrySeq extends chiSubordinateSeq;
  `uvm_object_utils(chiSubordinateRetrySeq)

  function new(string name = "chiSubordinateRetrySeq");
    super.new(name);
  endfunction

  task body();
    p_sequencer.cfg.enableRetry = 1'b1;
  endtask
endclass

// Split every write completion into DBIDResp and a separate Comp, and drop
// the optional ReadReceipt. Both alternatives of both flows are legal, so a
// DUT that only works against one of them is broken and this is what finds
// out. [SPEC:IHI0050H B2.3.9.1] [SPEC:IHI0050H B2.3.9.2]
class chiSubordinateSeparateRespSeq extends chiSubordinateSeq;
  `uvm_object_utils(chiSubordinateSeparateRespSeq)

  function new(string name = "chiSubordinateSeparateRespSeq");
    super.new(name);
  endfunction

  task body();
    chiSubordinateTx rule;
    rule = chiSubordinateTx::type_id::create("rule");
    start_item(rule);
    if (!rule.randomize() with {
      matchKind == CHI_SN_MATCH_ALL;
      respErr == RESP_ERR_OK;
      useCount == 0;
      forceSeparateWriteResp == 1'b1;
      suppressReadReceipt == 1'b1;
    })
      `uvm_fatal("chiSubordinateSeparateRespSeq", "separate rule randomize failed")
    finish_item(rule);
  endtask
endclass

// Base sequence. Tests extend it and call chiSendIntent. finish_item
// returns once the driver has accepted the item; get_response waits
// until the completion thread has applied the response to the cache model.

class chiRequesterSeq extends uvm_sequence#(chiRequesterTx);
  bit pinPoison;
  logic [7:0] poisonValue;
  bit pinDataCheck;
  logic [63:0] dataCheckValue;
  bit pinMpam;
  logic [14:0] mpamValue;
  bit pinPbha;
  logic [PBHA_W-1:0] pbhaValue;
  bit pinTagOp;
  logic [TAG_OP_W-1:0] tagOpValue;

  `uvm_object_utils(chiRequesterSeq)
  `uvm_declare_p_sequencer(chiRequesterSequencer)

  function new(string name = "chiRequesterSeq");
    super.new(name);
    pinPoison = 1'b0;
    pinDataCheck = 1'b0;
    pinMpam = 1'b0;
    pinPbha = 1'b0;
    pinTagOp = 1'b0;
    poisonValue = '0;
    dataCheckValue = '0;
    mpamValue = '0;
    pbhaValue = '0;
    tagOpValue = '0;
  endfunction

  task body();
  endtask

  task chiSendIntent(
    input chiRequesterIntentE intent,
    input chiAddrT addr,
    input logic [SIZE_W-1:0] size = SIZE_W'(6),
    input logic [ORDER_W-1:0] order = '0,
    input bit expCompAck = 1'b1
  );
    chiRequesterTx item;
    chiRequesterTx rsp;
    chiPostIntent(intent, addr, size, order, expCompAck, item);
    get_response(rsp);
  endtask

  task chiPostIntent(
    input chiRequesterIntentE intent,
    input chiAddrT addr,
    input logic [SIZE_W-1:0] size,
    input logic [ORDER_W-1:0] order,
    input bit expCompAck,
    output chiRequesterTx item
  );
    item = chiRequesterTx::type_id::create("item");
    start_item(item);
    item.nodeClass = p_sequencer.cfg.nodeClass;
    item.intent = intent;
    item.addr = addr;
    item.size = size;
    item.order = order;
    item.intent.rand_mode(0);
    item.addr.rand_mode(0);
    item.size.rand_mode(0);
    item.order.rand_mode(0);
    // Three intents have no say in ExpCompAck: DVM and PCrdReturn take no
    // CompAck, and PrefetchTgt takes no response at all.
    // [SPEC:IHI0050H B4.2.6.2]
    if (!(intent inside {CHI_INTENT_DVM_OP, CHI_INTENT_PCRD_RETURN,
                         CHI_INTENT_PREFETCH_TGT})) begin
      item.expCompAck = expCompAck;
      item.expCompAck.rand_mode(0);
    end
    if (pinPoison) begin
      item.poison = poisonValue;
      item.poison.rand_mode(0);
    end
    if (pinDataCheck) begin
      item.dataCheck = dataCheckValue;
      item.dataCheck.rand_mode(0);
    end
    if (pinMpam) begin
      item.mpam = mpamValue;
      item.mpam.rand_mode(0);
    end
    if (pinPbha) begin
      item.pbha = pbhaValue;
      item.pbha.rand_mode(0);
    end
    if (pinTagOp) begin
      item.tagOp = tagOpValue;
      item.tagOp.rand_mode(0);
    end
    if (!item.randomize())
      `uvm_fatal("chiRequesterSeq", "intent randomize failed")
    finish_item(item);
  endtask

  task chiBurstIntent(
    input chiRequesterIntentE intent,
    input int unsigned count,
    input int unsigned lineBase
  );
    chiRequesterTx item;
    chiRequesterTx rsp;
    for (int unsigned i = 0; i < count; i++)
      chiPostIntent(intent, coherentLineAddr(lineBase + i), SIZE_W'(6), '0, 1'b1, item);
    for (int unsigned i = 0; i < count; i++)
      get_response(rsp);
  endtask
endclass

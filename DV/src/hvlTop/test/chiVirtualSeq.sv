// Starts per-port sequences on the virtual sequencer. A mode selects
// the traffic. Feature pins are copied onto the requester sequence so
// a directed test can override poison, MPAM, PBHA, or TagOp.

typedef enum int unsigned {
  CHI_VSEQ_NONE,
  CHI_VSEQ_COHERENT,
  CHI_VSEQ_SHARED,
  CHI_VSEQ_RETRY,
  CHI_VSEQ_READ,
  CHI_VSEQ_RND_READ,
  CHI_VSEQ_ORDER,
  CHI_VSEQ_ZERO,
  CHI_VSEQ_CMO,
  CHI_VSEQ_ATOMIC,
  CHI_VSEQ_DVM,
  CHI_VSEQ_STASH,
  CHI_VSEQ_EXCL,
  CHI_VSEQ_WRITE,
  CHI_VSEQ_BURST,
  CHI_VSEQ_POISON,
  CHI_VSEQ_RESP_ERR
} chiVirtualSeqModeE;

class chiVirtualSeq extends uvm_sequence;
  chiVirtualSeqModeE mode;
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

  `uvm_object_utils(chiVirtualSeq)
  `uvm_declare_p_sequencer(chiVirtualSequencer)

  function new(string name = "chiVirtualSeq");
    super.new(name);
    mode = CHI_VSEQ_NONE;
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

  function void chiCopyPins(chiRequesterSeq seq);
    seq.pinPoison = pinPoison;
    seq.poisonValue = poisonValue;
    seq.pinDataCheck = pinDataCheck;
    seq.dataCheckValue = dataCheckValue;
    seq.pinMpam = pinMpam;
    seq.mpamValue = mpamValue;
    seq.pinPbha = pinPbha;
    seq.pbhaValue = pbhaValue;
    seq.pinTagOp = pinTagOp;
    seq.tagOpValue = tagOpValue;
  endfunction

  task chiRnf(
    input int unsigned index,
    input chiRequesterIntentE intent,
    input chiAddrT addr,
    input logic [SIZE_W-1:0] size = SIZE_W'(6),
    input logic [ORDER_W-1:0] order = '0
  );
    chiOneIntentSeq seq;
    if (index >= p_sequencer.rnfSeqr.size())
      `uvm_fatal("chiVirtualSeq", {$sformatf("RN-F %0d has no sequencer", index)})
    seq = chiOneIntentSeq::type_id::create($sformatf("rnfSeq%0d", index));
    seq.intent = intent;
    seq.addr = addr;
    seq.size = size;
    seq.order = order;
    chiCopyPins(seq);
    seq.start(p_sequencer.rnfSeqr[index]);
  endtask

  task chiRnd(
    input int unsigned index,
    input chiRequesterIntentE intent,
    input chiAddrT addr
  );
    chiOneIntentSeq seq;
    if (index >= p_sequencer.rndSeqr.size())
      `uvm_fatal("chiVirtualSeq", {$sformatf("RN-D %0d has no sequencer", index)})
    seq = chiOneIntentSeq::type_id::create($sformatf("rndSeq%0d", index));
    seq.intent = intent;
    seq.addr = addr;
    seq.size = SIZE_W'(6);
    seq.order = '0;
    chiCopyPins(seq);
    seq.start(p_sequencer.rndSeqr[index]);
  endtask

  task chiBurst(input int unsigned index, input int unsigned count, input int unsigned lineBase);
    chiBurstIntentSeq seq;
    if (index >= p_sequencer.rnfSeqr.size())
      `uvm_fatal("chiVirtualSeq", {$sformatf("RN-F %0d has no sequencer", index)})
    seq = chiBurstIntentSeq::type_id::create("burstSeq");
    seq.intent = CHI_INTENT_READ_NO_SNP;
    seq.count = count;
    seq.lineBase = lineBase;
    chiCopyPins(seq);
    seq.start(p_sequencer.rnfSeqr[index]);
  endtask

  task chiAllRetry();
    foreach (p_sequencer.snfSeqr[i]) begin
      chiSubordinateRetrySeq seq;
      seq = chiSubordinateRetrySeq::type_id::create($sformatf("retrySnf%0d", i));
      seq.start(p_sequencer.snfSeqr[i]);
    end
    foreach (p_sequencer.sniSeqr[i]) begin
      chiSubordinateRetrySeq seq;
      seq = chiSubordinateRetrySeq::type_id::create($sformatf("retrySni%0d", i));
      seq.start(p_sequencer.sniSeqr[i]);
    end
  endtask

  task chiAllRespErr();
    foreach (p_sequencer.snfSeqr[i]) begin
      chiSubordinateRespErrSeq seq;
      seq = chiSubordinateRespErrSeq::type_id::create($sformatf("respErrSnf%0d", i));
      seq.start(p_sequencer.snfSeqr[i]);
    end
    foreach (p_sequencer.sniSeqr[i]) begin
      chiSubordinateRespErrSeq seq;
      seq = chiSubordinateRespErrSeq::type_id::create($sformatf("respErrSni%0d", i));
      seq.start(p_sequencer.sniSeqr[i]);
    end
  endtask

  task body();
    case (mode)
      CHI_VSEQ_COHERENT: begin
        chiRnf(0, CHI_INTENT_READ_SHARED, coherentLineAddr(1));
        chiRnf(0, CHI_INTENT_READ_UNIQUE, coherentLineAddr(2));
        chiRnf(0, CHI_INTENT_WRITE_BACK, coherentLineAddr(2));
      end
      CHI_VSEQ_SHARED: begin
        chiRnf(0, CHI_INTENT_READ_SHARED, coherentLineAddr(4));
        chiRnf(1, CHI_INTENT_READ_SHARED, coherentLineAddr(4));
        chiRnf(0, CHI_INTENT_READ_UNIQUE, coherentLineAddr(4));
      end
      CHI_VSEQ_RETRY: begin
        chiAllRetry();
        chiRnf(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(5));
        chiRnf(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(6));
        chiRnf(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(7));
      end
      CHI_VSEQ_READ: chiRnf(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(8));
      CHI_VSEQ_RND_READ: chiRnd(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(8));
      CHI_VSEQ_ORDER: chiRnf(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(9), SIZE_W'(6), 2'b01);
      CHI_VSEQ_ZERO: begin
        chiRnf(0, CHI_INTENT_WRITE_NO_SNP_ZERO, coherentLineAddr(10));
        chiRnf(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(10));
      end
      CHI_VSEQ_CMO: begin
        chiRnf(0, CHI_INTENT_CLEAN_SHARED, coherentLineAddr(11));
        chiRnf(0, CHI_INTENT_CLEAN_INVALID, coherentLineAddr(12));
        chiRnf(0, CHI_INTENT_MAKE_INVALID, coherentLineAddr(13));
      end
      CHI_VSEQ_ATOMIC: chiRnf(0, CHI_INTENT_ATOMIC_LOAD, coherentLineAddr(14), SIZE_W'(3));
      CHI_VSEQ_DVM: chiRnf(0, CHI_INTENT_DVM_OP, coherentLineAddr(15));
      CHI_VSEQ_STASH: chiRnf(0, CHI_INTENT_STASH_ONCE, coherentLineAddr(16));
      CHI_VSEQ_EXCL: begin
        chiRnf(0, CHI_INTENT_EXCLUSIVE_LOAD, coherentLineAddr(17));
        chiRnf(0, CHI_INTENT_EXCLUSIVE_STORE, coherentLineAddr(17));
      end
      CHI_VSEQ_WRITE: chiRnf(0, CHI_INTENT_WRITE_NO_SNP, coherentLineAddr(18));
      CHI_VSEQ_BURST: chiBurst(0, 8, 20);
      CHI_VSEQ_POISON: begin
        chiRnf(0, CHI_INTENT_WRITE_NO_SNP, coherentLineAddr(30));
        chiRnf(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(30));
      end
      CHI_VSEQ_RESP_ERR: begin
        chiAllRespErr();
        chiRnf(0, CHI_INTENT_READ_NO_SNP, coherentLineAddr(31));
      end
      default: begin
      end
    endcase
  endtask
endclass

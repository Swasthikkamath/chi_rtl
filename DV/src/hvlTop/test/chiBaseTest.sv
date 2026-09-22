// Base test. The default run holds an objection long enough for every
// active link to reach RUN and then deactivate. A subclass overrides
// chiRun and starts chiVirtualSeq on env.virtualSequencer.
// [ASSUMPTION:16] [ASSUMPTION:18]

class chiBaseTest extends uvm_test;
  topEnv env;
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

  `uvm_component_utils(chiBaseTest)

  function new(string name = "chiBaseTest", uvm_component parent = null);
    super.new(name, parent);
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

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = topEnv::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    chiRun();
    phase.drop_objection(this);
  endtask

  task chiRun();
    #1us;
  endtask

  function bit chiSkip(input bit blocked, input string label);
    if (blocked) begin
      `uvm_info("SKIP",
        {$sformatf("%s disabled: %s reports SKIP", get_type_name(), label)}, UVM_NONE)
      return 1'b1;
    end
    return 1'b0;
  endfunction

  function bit chiGate(input bit enabled, input string label);
    return !chiSkip(!enabled, label);
  endfunction

  task chiStart(input chiVirtualSeqModeE mode);
    chiVirtualSeq vseq;
    vseq = chiVirtualSeq::type_id::create("vseq");
    vseq.mode = mode;
    vseq.pinPoison = pinPoison;
    vseq.poisonValue = poisonValue;
    vseq.pinDataCheck = pinDataCheck;
    vseq.dataCheckValue = dataCheckValue;
    vseq.pinMpam = pinMpam;
    vseq.mpamValue = mpamValue;
    vseq.pinPbha = pinPbha;
    vseq.pbhaValue = pbhaValue;
    vseq.pinTagOp = pinTagOp;
    vseq.tagOpValue = tagOpValue;
    vseq.start(env.virtualSequencer);
  endtask
endclass

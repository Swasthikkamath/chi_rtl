// Drives odd byte parity on RN-F 0 and expects linkParityError.
// The DUT checks even parity. Skips when parityEn is clear.
// [ASSUMPTION:17] See OPEN QUESTIONS finding F-1.

class chiParityTest extends chiBaseTest;
  `uvm_component_utils(chiParityTest)

  function new(string name = "chiParityTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    virtual chiRequesterDriverBfm bfm;
    string key;
    if (!chiGate(CHI_CFG.parityEn, "parityEn"))
      return;
    key = requesterDriverBfmKey(OFF_RNF);
    if (!uvm_config_db#(virtual chiRequesterDriverBfm)::get(null, "*", key, bfm))
      `uvm_fatal("chiParityTest", {"config_db get failed for key ", key})
    bfm.injectOddParity = 1'b1;
    env.scoreboard.linkModel.expectParityError = 1'b1;
    chiStart(CHI_VSEQ_READ);
    bfm.injectOddParity = 1'b0;
  endtask
endclass

// Sends without a credit once the RN-F 0 credit count is already 0.
// A missing linkCreditError is a warning: the DUT may have replenished
// the credit before the illegal send. [ASSUMPTION:9] [ASSUMPTION:17]
// See OPEN QUESTIONS Q17.

class chiCreditErrorTest extends chiBaseTest;
  `uvm_component_utils(chiCreditErrorTest)

  function new(string name = "chiCreditErrorTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    virtual chiRequesterDriverBfm bfm;
    string key;
    key = requesterDriverBfmKey(OFF_RNF);
    if (!uvm_config_db#(virtual chiRequesterDriverBfm)::get(null, "*", key, bfm))
      `uvm_fatal("chiCreditErrorTest", {"config_db get failed for key ", key})
    bfm.injectSendWithoutCredit = 1'b1;
    env.scoreboard.linkModel.expectCreditError = 1'b1;
    chiStart(CHI_VSEQ_BURST);
    bfm.injectSendWithoutCredit = 1'b0;
  endtask
endclass

// Policy for one subordinate port. This is not a request. The driver
// applies it to the shared config and keeps answering REQ on its own
// thread, so a sequence cannot choose a target.
// [TOP:reqToNoc] [ASSUMPTION:15]

class chiSubordinateTx extends uvm_sequence_item;
  rand bit enableRetry;
  rand chiRespErrE injectRespErr;

  constraint chiLegalPolicy {
    injectRespErr inside {RESP_ERR_OK, RESP_ERR_EXOK, RESP_ERR_DERR, RESP_ERR_NDERR};
  }

  `uvm_object_utils(chiSubordinateTx)

  function new(string name = "chiSubordinateTx");
    super.new(name);
    enableRetry = 1'b0;
    injectRespErr = RESP_ERR_OK;
  endfunction
endclass

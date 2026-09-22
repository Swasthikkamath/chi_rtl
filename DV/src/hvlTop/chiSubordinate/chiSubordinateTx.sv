// A Subordinate is reactive: nothing it does starts with a sequence, it
// starts with a request arriving on the wire. So this item is not "send
// this", it is "when a request that looks like this arrives, answer it like
// that". The driver consults the sequencer before each response and falls
// back to the config defaults when no rule matches.
//
// A rule with matchAll set applies to every request, which is how a test
// changes global policy for a window without enumerating addresses.

typedef enum bit [1:0] {
  CHI_SN_MATCH_ALL     = 2'd0,  // any request
  CHI_SN_MATCH_ADDR    = 2'd1,  // requests to one cache line
  CHI_SN_MATCH_OPCODE  = 2'd2,  // requests carrying one opcode
  CHI_SN_MATCH_BOTH    = 2'd3   // both of the above
} chiSnMatchE;

class chiSubordinateTx extends uvm_sequence_item;
  rand chiSnMatchE matchKind;
  rand chiAddrT matchAddr;
  rand chiReqOpcodeE matchOpcode;

  // How many matching requests this rule covers before it retires. Zero
  // means it never retires.
  rand int unsigned useCount;

  // What to do with a matching request.
  rand chiRespErrE respErr;
  rand bit forceSeparateWriteResp;
  rand bit suppressReadReceipt;
  rand int unsigned extraDelay;

  // Corrupt the returned read data. Separate from respErr because the
  // interesting case is silent corruption with RespErr still OK, which is
  // what an end-to-end data check has to catch on its own.
  rand bit corruptReadData;

  // Filled in by the driver so a sequence can see what its rule matched.
  chiAddrT lastMatchAddr;
  chiReqOpcodeE lastMatchOpcode;

  constraint chiDelayC {
    extraDelay inside {[0:32]};
  }

  constraint chiUseCountC {
    useCount inside {[0:64]};
  }

  constraint chiDefaultsC {
    soft respErr == RESP_ERR_OK;
    soft corruptReadData == 1'b0;
    soft forceSeparateWriteResp == 1'b0;
    soft suppressReadReceipt == 1'b0;
  }

  constraint chiAddrAlignC {
    matchAddr[5:0] == '0;
  }

  `uvm_object_utils_begin(chiSubordinateTx)
    `uvm_field_enum(chiSnMatchE, matchKind, UVM_ALL_ON)
    `uvm_field_int(matchAddr, UVM_ALL_ON)
    `uvm_field_enum(chiReqOpcodeE, matchOpcode, UVM_ALL_ON)
    `uvm_field_int(useCount, UVM_ALL_ON)
    `uvm_field_enum(chiRespErrE, respErr, UVM_ALL_ON)
    `uvm_field_int(forceSeparateWriteResp, UVM_ALL_ON)
    `uvm_field_int(suppressReadReceipt, UVM_ALL_ON)
    `uvm_field_int(extraDelay, UVM_ALL_ON)
    `uvm_field_int(corruptReadData, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "chiSubordinateTx");
    super.new(name);
    matchKind = CHI_SN_MATCH_ALL;
    matchAddr = '0;
    matchOpcode = REQ_READ_NO_SNP;
    useCount = 0;
    respErr = RESP_ERR_OK;
    forceSeparateWriteResp = 1'b0;
    suppressReadReceipt = 1'b0;
    extraDelay = 0;
    corruptReadData = 1'b0;
  endfunction

  function bit chiMatches(input chiAddrT addr, input chiReqOpcodeE opcode);
    case (matchKind)
      CHI_SN_MATCH_ALL:    return 1'b1;
      CHI_SN_MATCH_ADDR:   return lineAlign(addr) == lineAlign(matchAddr);
      CHI_SN_MATCH_OPCODE: return opcode == matchOpcode;
      default:             return (lineAlign(addr) == lineAlign(matchAddr))
                                  && (opcode == matchOpcode);
    endcase
  endfunction
endclass

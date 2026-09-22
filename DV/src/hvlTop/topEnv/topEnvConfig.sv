// Build-time knobs for the integration environment. Counts and feature
// enables stay in CHI_CFG. A passive requester is holdQuiet: the driver
// holds the pins at STOP and issues nothing.
// [ASSUMPTION:18]

class topEnvConfig extends uvm_object;
  bit holdQuietRnf[int unsigned];
  bit holdQuietRnd[int unsigned];
  bit holdQuietRni[int unsigned];
  bit holdQuietSnf[int unsigned];
  bit holdQuietSni[int unsigned];

  `uvm_object_utils(topEnvConfig)

  function new(string name = "topEnvConfig");
    super.new(name);
  endfunction

  function bit chiHoldQuiet(input chiNodeClassE nodeClass, input int unsigned index);
    case (nodeClass)
      RN_F: return holdQuietRnf.exists(index);
      RN_D: return holdQuietRnd.exists(index);
      RN_I: return holdQuietRni.exists(index);
      SN_F: return holdQuietSnf.exists(index);
      default: return holdQuietSni.exists(index);
    endcase
  endfunction
endclass

// Passive reconstruction of one Requester port's activity.
//
// Everything published here comes from the pins by way of the monitor BFM, not
// from the driver. That independence is the point: if the driver builds a flit
// with the wrong field, the monitor reports the wrong field, and the
// scoreboard sees a mismatch. A monitor fed from driver state would agree with
// the driver about anything the driver got wrong.
//
// One analysis port carries both protocol flits and link events, distinguished
// by txKind. Two ports would mean two FIFOs and two subscribe paths in every
// subscriber for what is a single stream of observations from a single
// interface.
class chiRequesterMonitorProxy extends uvm_monitor;

  chiRequesterAgentConfig  cfg;
  virtual chiMonitorBfm    bfm;

  uvm_analysis_port #(chiRequesterTx) analysisPort;

  protected int unsigned flitsSeen;
  protected int unsigned eventsSeen;

  `uvm_component_utils(chiRequesterMonitorProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysisPort = new("analysisPort", this);
  endfunction

  task run_phase(uvm_phase phase);
    fork
      flitLoop();
      eventLoop();
    join
  endtask

  protected task flitLoop();
    chiSampledFlitS sample;
    chiRequesterTx  tx;
    forever begin
      bfm.getFlit(sample);
      tx = chiRequesterTx::type_id::create("tx");
      tx.txKind    = CHI_TX_PROTOCOL_FLIT;
      tx.direction = sample.direction;
      tx.channel   = sample.channel;
      tx.agentId   = cfg.agentId;
      tx.nodeClass = cfg.nodeClass;

      // Each channel is unpacked with its own function, which is why the
      // channel travels with the sample. Only REQ and SNP carry an address, so
      // only those two set one.
      tx.addr      = '0;
      tx.addrValid = 1'b0;
      case (sample.channel)
        CHI_CHANNEL_REQ: begin
          tx.reqFlit   = unpackReqFlit(CHI_CFG,
              sample.flit[CHI_MAX_REQ_FLIT_W-1:0]);
          tx.addr      = tx.reqFlit.addr;
          tx.addrValid = 1'b1;
          tx.size      = tx.reqFlit.size;
          tx.qos       = tx.reqFlit.qos;
        end
        CHI_CHANNEL_RSP:
          tx.rspFlit = unpackRspFlit(CHI_CFG,
              sample.flit[CHI_MAX_RSP_FLIT_W-1:0]);
        CHI_CHANNEL_SNP: begin
          tx.snpFlit   = unpackSnpFlit(CHI_CFG,
              sample.flit[CHI_MAX_SNP_FLIT_W-1:0]);
          tx.addr      = {tx.snpFlit.addr, 3'b000};
          tx.addrValid = 1'b1;
        end
        default:
          tx.datFlit = unpackDatFlit(CHI_CFG,
              sample.flit[CHI_MAX_DAT_FLIT_W-1:0]);
      endcase

      flitsSeen++;
      `uvm_info(get_type_name(), tx.convert2string(), UVM_DEBUG)
      analysisPort.write(tx);
    end
  endtask

  protected task eventLoop();
    chiLinkEventS  event_;
    chiRequesterTx tx;
    forever begin
      bfm.getLinkEvent(event_);
      tx = chiRequesterTx::type_id::create("tx");
      tx.txKind    = CHI_TX_LINK_EVENT;
      tx.linkEvent = event_;
      tx.direction = event_.direction;
      tx.channel   = event_.channel;
      tx.agentId   = cfg.agentId;
      tx.nodeClass = cfg.nodeClass;
      eventsSeen++;
      analysisPort.write(tx);
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
              $sformatf("agent %0d %s: %0d flits, %0d link events observed",
                        cfg.agentId, cfg.nodeClass.name(), flitsSeen,
                        eventsSeen), UVM_LOW)
  endfunction
endclass

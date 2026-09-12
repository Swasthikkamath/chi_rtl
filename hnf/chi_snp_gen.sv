module chi_snp_gen #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_RNF = (CFG.numRnf > 0) ? CFG.numRnf : 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    RNF_NODE_IDS [NUM_RNF] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] HN_NODE_ID = '0
) (
  input  logic clk,
  input  logic resetn,
  input  logic startValid,
  output logic startReady,
  input  logic [NUM_RNF-1:0] startSharers,
  input  logic [CFG.addrW-7:0] startLineAddr,
  input  chi_pkg::chi_snp_opcode_e startOpcode,
  input  logic [CFG.txnIdW-1:0] startTxnId,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] startFwdNid,
  input  logic [CFG.txnIdW-1:0] startFwdTxnId,
  input  logic startRetToSrc,
  input  chi_pkg::chi_pas_e startPas,
  input  logic [NUM_RNF-1:0] startStashTarget,
  input  chi_pkg::chi_snp_opcode_e startStashOpcode,
  input  logic startStashLpidValid,
  input  logic [chi_cfg_pkg::CHI_MAX_LPID_W-1:0] startStashLpid,
  output logic snpValid,
  input  logic snpReady,
  output chi_pkg::chi_noc_flit_t snpFlit,
  input  logic responseValid,
  output logic responseReady,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] responseSource,
  input  logic responseDataPull,
  input  logic [chi_cfg_pkg::CHI_RSP_DBID_SLOT_W-1:0] responseDbId,
  output logic dataPullValid,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] dataPullTarget,
  output logic [chi_cfg_pkg::CHI_RSP_DBID_SLOT_W-1:0] dataPullTxnId,
  output logic busy,
  output logic done
);
  import chi_pkg::*;

  typedef enum logic [1:0] {SNP_IDLE, SNP_SEND, SNP_WAIT} snp_state_e;
  snp_state_e state;
  logic [NUM_RNF-1:0] remaining;
  logic [clog2Min1(NUM_RNF)-1:0] selected;
  logic selectedValid;
  logic [CFG.addrW-7:0] lineAddrReg;
  chi_snp_opcode_e opcodeReg;
  logic [CFG.txnIdW-1:0] txnIdReg;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] fwdNidReg;
  logic [CFG.txnIdW-1:0] fwdTxnIdReg;
  logic retToSrcReg;
  chi_pas_e pasReg;
  logic [NUM_RNF-1:0] stashTargetReg;
  chi_snp_opcode_e stashOpcodeReg;
  logic stashLpidValidReg;
  logic [chi_cfg_pkg::CHI_MAX_LPID_W-1:0] stashLpidReg;
  logic selectedIsStashTarget;
  chi_snp_flit_t protocolFlit;

  always_comb begin
    selected = '0;
    selectedValid = 1'b0;
    for (int unsigned i = 0; i < NUM_RNF; i++) begin
      if (!selectedValid && remaining[i]) begin
        selected = i[clog2Min1(NUM_RNF)-1:0];
        selectedValid = 1'b1;
      end
    end

    selectedIsStashTarget = selectedValid && stashTargetReg[selected];

    protocolFlit = '0;
    protocolFlit.srcId = HN_NODE_ID;
    protocolFlit.txnId = txnIdReg;
    protocolFlit.fwdNidOrPbha = fwdNidReg;
    protocolFlit.fwdTxnIdOrStashLpidOrVmidExt = fwdTxnIdReg;
    // For the stash target the shared 12-bit slot carries
    // {6'b0, StashLPIDValid, StashLPID} instead of FwdTxnID
    // (IHI 0050H Table B13.8).
    if (selectedIsStashTarget)
      protocolFlit.fwdTxnIdOrStashLpidOrVmidExt =
        {{(chi_cfg_pkg::CHI_RTNTXNID_SLOT_W - chi_cfg_pkg::CHI_MAX_LPID_W - 1)
            {1'b0}}, stashLpidValidReg, stashLpidReg};
    protocolFlit.opcode = selectedIsStashTarget ? stashOpcodeReg : opcodeReg;
    protocolFlit.addr = '0;
    protocolFlit.addr[CFG.addrW-4:0] = {lineAddrReg, 3'b000};
    protocolFlit.pas = pasReg;
    protocolFlit.retToSrc = retToSrcReg;

    snpFlit = '0;
    snpFlit.channel = CHI_CHANNEL_SNP;
    snpFlit.targetNodeId = RNF_NODE_IDS[selected];
    snpFlit.payload[CHI_MAX_SNP_FLIT_W-1:0] = packSnpFlit(CFG, protocolFlit);
    snpValid = (state == SNP_SEND) && selectedValid;
    responseReady = (state == SNP_WAIT)
                    && (responseSource == RNF_NODE_IDS[selected]);
    startReady = state == SNP_IDLE;
    busy = state != SNP_IDLE;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      state <= SNP_IDLE;
      remaining <= '0;
      lineAddrReg <= '0;
      opcodeReg <= SNP_SHARED;
      txnIdReg <= '0;
      fwdNidReg <= '0;
      fwdTxnIdReg <= '0;
      retToSrcReg <= 1'b0;
      pasReg <= PAS_SECURE;
      stashTargetReg <= '0;
      stashOpcodeReg <= SNP_STASH_SHARED;
      stashLpidValidReg <= 1'b0;
      stashLpidReg <= '0;
      dataPullValid <= 1'b0;
      dataPullTarget <= '0;
      dataPullTxnId <= '0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      case (state)
        SNP_IDLE: begin
          if (startValid) begin
            remaining <= startSharers;
            lineAddrReg <= startLineAddr;
            opcodeReg <= startOpcode;
            txnIdReg <= startTxnId;
            fwdNidReg <= startFwdNid;
            fwdTxnIdReg <= startFwdTxnId;
            retToSrcReg <= startRetToSrc;
            pasReg <= startPas;
            stashTargetReg <= startStashTarget;
            stashOpcodeReg <= startStashOpcode;
            stashLpidValidReg <= startStashLpidValid;
            stashLpidReg <= startStashLpid;
            dataPullValid <= 1'b0;
            dataPullTarget <= '0;
            dataPullTxnId <= '0;
            if (startSharers == '0)
              done <= 1'b1;
            else
              state <= SNP_SEND;
          end
        end
        SNP_SEND: begin
          if (snpValid && snpReady)
            state <= SNP_WAIT;
        end
        SNP_WAIT: begin
          if (responseValid && responseReady) begin
            // A stash target that wants the line answers with DataPull set
            // and names the TxnID the Home must use for the implied read in
            // the DBID field (IHI 0050H B7.3).
            if (selectedIsStashTarget && responseDataPull) begin
              dataPullValid <= 1'b1;
              dataPullTarget <= RNF_NODE_IDS[selected];
              dataPullTxnId <= responseDbId;
            end
            remaining[selected] <= 1'b0;
            if ((remaining & ~(NUM_RNF'(1) << selected)) == '0) begin
              state <= SNP_IDLE;
              done <= 1'b1;
            end else begin
              state <= SNP_SEND;
            end
          end
        end
        default: state <= SNP_IDLE;
      endcase
    end
  end
endmodule

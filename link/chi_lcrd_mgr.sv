module chi_lcrd_mgr #(
  parameter int unsigned LCRD_DEPTH = 8,
  parameter int unsigned COUNT_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH + 1)
) (
  input  logic               clk,
  input  logic               resetn,
  input  logic               creditGrant,
  input  logic               creditReturn,
  input  logic               creditConsume,
  output logic [COUNT_W-1:0] creditCount,
  output logic               creditAvailable,
  output logic               creditsFull,
  output logic               overflow,
  output logic               underflow
);
  localparam logic [COUNT_W-1:0] LCRD_DEPTH_COUNT =
    COUNT_W'(LCRD_DEPTH);
  localparam logic [COUNT_W+1:0] LCRD_DEPTH_EXT =
    (COUNT_W + 2)'(LCRD_DEPTH);

  logic [COUNT_W+1:0] incrementCount;
  logic [COUNT_W+1:0] nextCount;

  always_comb begin
    incrementCount = {{(COUNT_W+1){1'b0}}, creditGrant}
                   + {{(COUNT_W+1){1'b0}}, creditReturn};
    nextCount = {{2{1'b0}}, creditCount};
    overflow = 1'b0;
    underflow = 1'b0;

    if (creditConsume) begin
      if (nextCount == '0) begin
        underflow = 1'b1;
      end else begin
        nextCount = nextCount - 1'b1;
      end
    end

    if (incrementCount != '0) begin
      if ((nextCount + incrementCount) > LCRD_DEPTH_EXT) begin
        nextCount = LCRD_DEPTH_EXT;
        overflow = 1'b1;
      end else begin
        nextCount = nextCount + incrementCount;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      creditCount <= '0;
    end else begin
      creditCount <= nextCount[COUNT_W-1:0];
    end
  end

  always_comb begin
    creditAvailable = (creditCount != '0);
    creditsFull = (creditCount == LCRD_DEPTH_COUNT);
  end
endmodule

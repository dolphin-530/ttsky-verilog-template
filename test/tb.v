``default_nettype none
`timescale 1ns / 1ps

/* Testbench scaffold for cocotb:
   - Generates clk
   - Drives reset/enable
   - Initializes inputs
   - Dumps FST for waveform viewing
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // 100 MHz clock (10 ns period)
  localparam integer CLK_PERIOD_NS = 10;
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD_NS/2) clk = ~clk;
  end

  // Basic init/reset sequence so cocotb starts from a known state
  initial begin
    // defaults
    ena    = 1'b0;
    rst_n  = 1'b0;
    ui_in  = 8'h00;
    uio_in = 8'h00;

    // hold reset a few cycles
    repeat (5) @(posedge clk);
    ena   <= 1'b1;
    repeat (2) @(posedge clk);
    rst_n <= 1'b1;

    // leave running; cocotb will drive ui_in/uio_in as needed
  end

  // Replace tt_um_example with your module name:
  // (If your top module is tt_self_timed_sync_model, change it here.)
  tt_self_timed_sync_model user_project (

`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

endmodule
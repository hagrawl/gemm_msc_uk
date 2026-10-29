`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2026 10:37:03 AM
// Design Name: 
// Module Name: tb_pe2
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_pe2;
  // --------------------------------------------------
  // Parameters
  // --------------------------------------------------
  localparam DW_A  = 8;
  localparam DW_B  = 8;
  localparam ACC_W = 32;
  localparam PROD_W = DW_A + DW_B;

  // --------------------------------------------------
  // DUT inputs
  // --------------------------------------------------
  logic clk;
  logic rst_n;
  logic acc_clear;

  logic signed [DW_A-1:0] a_in;
  logic signed [DW_B-1:0] b_in;

  logic a_valid_in;
  logic b_valid_in;

  // --------------------------------------------------
  // DUT outputs
  // --------------------------------------------------
  logic signed [DW_A-1:0] a_out;
  logic signed [DW_B-1:0] b_out;

  logic a_out_valid;
  logic b_out_valid;

  logic signed [ACC_W-1:0] acc_out;
  logic acc_out_valid;

  // --------------------------------------------------
  // Instantiate DUT
  // --------------------------------------------------
  pe #(
    .DW_a(DW_A),
    .DW_b(DW_B),
    .Acc_ip_width(ACC_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .acc_clear(acc_clear),

    .a_in(a_in),
    .a_valid_in(a_valid_in),

    .b_in(b_in),
    .b_valid_in(b_valid_in),

    .a_out(a_out),
    .a_out_valid(a_out_valid),

    .b_out(b_out),
    .b_out_valid(b_out_valid),

    .acc_out(acc_out),
    .acc_out_valid(acc_out_valid)
  );

  // --------------------------------------------------
  // Clock: 10 ns period
  // --------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // --------------------------------------------------
  // Reference model
  //
  // Models the product register between Stage 0 and
  // Stage 1, followed by signed accumulation.
  // --------------------------------------------------
  logic signed [PROD_W-1:0] model_product;
  logic model_product_valid;

  logic signed [ACC_W-1:0] model_acc;
  logic model_acc_valid;

  integer checks = 0;
  integer errors = 0;

  // --------------------------------------------------
  // Scoreboard
  // --------------------------------------------------
  always @(posedge clk) begin

    // Model reset behavior
    if (!rst_n) begin
      model_product       = '0;
      model_product_valid = 1'b0;
      model_acc           = '0;
      model_acc_valid     = 1'b0;
    end
    else begin

      // Stage 1: consume the PREVIOUS Stage 0 product
      if (acc_clear) begin
        model_acc       = '0;
        model_acc_valid = 1'b0;
      end
      else if (model_product_valid) begin
        model_acc = model_acc + model_product;
        model_acc_valid = 1'b1;
      end
      else begin
        // No new product: accumulator must hold
        model_acc_valid = 1'b0;
      end

      // Stage 0: prepare product for a FUTURE clock
      // Both inputs must be valid simultaneously.
      model_product_valid = a_valid_in && b_valid_in;

      if (a_valid_in && b_valid_in) begin
        model_product = a_in * b_in;
      end
    end

    // Compare after DUT nonblocking assignments settle
    #1;
    checks = checks + 1;

    if (acc_out !== model_acc) begin
      $error(
        "ACC MISMATCH at %0t: expected=%0d actual=%0d",
        $time, model_acc, acc_out
      );
      errors = errors + 1;
    end

    if (acc_out_valid !== model_acc_valid) begin
      $error(
        "VALID MISMATCH at %0t: expected=%b actual=%b",
        $time, model_acc_valid, acc_out_valid
      );
      errors = errors + 1;
    end

    $display(
      "T=%0t | A=%0d B=%0d | Vin=%b%b | Clear=%b | Expected=%0d | Actual=%0d | Valid=%b",
      $time, a_in, b_in, a_valid_in, b_valid_in,
      acc_clear, model_acc, acc_out, acc_out_valid
    );
  end

  // --------------------------------------------------
  // Drive one input transaction.
  // Inputs change on the falling edge to avoid races.
  // --------------------------------------------------
  task automatic drive(
    input logic signed [DW_A-1:0] a,
    input logic signed [DW_B-1:0] b,
    input logic va,
    input logic vb
  );
    @(negedge clk);
    a_in       = a;
    b_in       = b;
    a_valid_in = va;
    b_valid_in = vb;
  endtask

  // --------------------------------------------------
  // Clear accumulator for one clock cycle.
  // Inputs are kept invalid during clear.
  // --------------------------------------------------
  task automatic clear_accumulator;
    @(negedge clk);
    acc_clear  = 1'b1;
    a_valid_in = 1'b0;
    b_valid_in = 1'b0;

    @(negedge clk);
    acc_clear = 1'b0;
  endtask

  // --------------------------------------------------
  // Reset test
  // --------------------------------------------------
  task automatic reset_dut;
    @(negedge clk);
    rst_n      = 1'b0;
    acc_clear  = 1'b0;
    a_in       = '0;
    b_in       = '0;
    a_valid_in = 1'b0;
    b_valid_in = 1'b0;

    // Asynchronous reset should take effect without
    // waiting for the next positive clock edge.
    #1;
    if (acc_out !== '0) begin
      $error("Asynchronous reset failed: acc_out=%0d", acc_out);
      errors = errors + 1;
    end

    @(negedge clk);
    rst_n = 1'b1;
  endtask

  // --------------------------------------------------
  // Main test sequence
  // --------------------------------------------------
  integer i;
  integer seed;

  initial begin
    $display("\n========================================");
    $display(" Starting PE Self-Checking Testbench");
    $display("========================================\n");

    rst_n      = 1'b0;
    acc_clear  = 1'b0;
    a_in       = '0;
    b_in       = '0;
    a_valid_in = 1'b0;
    b_valid_in = 1'b0;

    // Allow reset to settle
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // ----------------------------------------------
    // TEST 1: Positive multiplication
    // ----------------------------------------------
    $display("\nTEST 1: Positive multiplication");

    drive(8'sd3, 8'sd4, 1'b1, 1'b1);
    drive(8'sd2, 8'sd5, 1'b1, 1'b1);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);

    // ----------------------------------------------
    // TEST 2: Negative and mixed-sign multiplication
    // ----------------------------------------------
    $display("\nTEST 2: Signed multiplication");

    drive(-8'sd3,  8'sd2, 1'b1, 1'b1);
    drive( 8'sd4, -8'sd5, 1'b1, 1'b1);
    drive(-8'sd6, -8'sd3, 1'b1, 1'b1);
    drive( 8'sd0,  8'sd0, 1'b0, 1'b0);

    // ----------------------------------------------
    // TEST 3: Back-to-back valid inputs
    // ----------------------------------------------
    $display("\nTEST 3: Consecutive valid inputs");

    drive(8'sd1, 8'sd2, 1'b1, 1'b1);
    drive(8'sd2, 8'sd3, 1'b1, 1'b1);
    drive(8'sd3, 8'sd4, 1'b1, 1'b1);
    drive(8'sd4, 8'sd5, 1'b1, 1'b1);
    drive(8'sd5, 8'sd6, 1'b1, 1'b1);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);

    // ----------------------------------------------
    // TEST 4: Invalid input combinations
    // ----------------------------------------------
    $display("\nTEST 4: Independent input-valid signals");

    drive(8'sd7, 8'sd3, 1'b1, 1'b0);
    drive(8'sd6, 8'sd2, 1'b0, 1'b1);
    drive(8'sd5, 8'sd4, 1'b0, 1'b0);
    drive(8'sd2, 8'sd3, 1'b1, 1'b1);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);

    // ----------------------------------------------
    // TEST 5: Accumulator clear and restart
    // ----------------------------------------------
    $display("\nTEST 5: Clear and restart");

    clear_accumulator();

    drive(8'sd3, 8'sd3, 1'b1, 1'b1);
    drive(8'sd2, 8'sd4, 1'b1, 1'b1);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);

    clear_accumulator();

    drive(-8'sd2, 8'sd5, 1'b1, 1'b1);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);

    // ----------------------------------------------
    // TEST 6: Signed boundary values
    // 8-bit signed range: -128 to +127
    // ----------------------------------------------
    $display("\nTEST 6: Signed boundary values");

    clear_accumulator();

    drive(-8'sd128,  8'sd1, 1'b1, 1'b1);
    drive( 8'sd127,  8'sd1, 1'b1, 1'b1);
    drive(-8'sd128, -8'sd1, 1'b1, 1'b1);
    drive( 8'sd0,    8'sd0, 1'b0, 1'b0);

    // ----------------------------------------------
    // TEST 7: Randomized valid/invalid transactions
    // ----------------------------------------------
    $display("\nTEST 7: Randomized testing");

    clear_accumulator();

    seed = 32'h1234ABCD;

    for (i = 0; i < 200; i = i + 1) begin
      logic signed [DW_A-1:0] rand_a;
      logic signed [DW_B-1:0] rand_b;
      logic rand_va;
      logic rand_vb;

      rand_a  = $signed($random(seed));
      rand_b  = $signed($random(seed));
      rand_va = $random(seed);
      rand_vb = $random(seed);

      drive(rand_a, rand_b, rand_va, rand_vb);
    end

    // Stop sending inputs and drain the pipeline
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);

    // ----------------------------------------------
    // TEST 8: Reset during operation
    // ----------------------------------------------
    $display("\nTEST 8: Reset during operation");

    drive(8'sd10, 8'sd10, 1'b1, 1'b1);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);
    reset_dut();

    drive(8'sd2, 8'sd3, 1'b1, 1'b1);
    drive(8'sd0, 8'sd0, 1'b0, 1'b0);

    // Drain pipeline and allow checks to complete
    repeat (3) @(negedge clk);

    $display("\n========================================");
    $display(" Checks completed: %0d", checks);
    $display(" Errors detected : %0d", errors);

    if (errors == 0)
      $display(" RESULT: ALL CHECKS PASSED");
    else
      $fatal(1, " RESULT: TEST FAILED");

    $display("========================================\n");

    $finish;
  end

endmodule

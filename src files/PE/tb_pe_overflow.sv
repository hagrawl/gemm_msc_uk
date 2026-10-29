`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2026 12:44:30 PM
// Design Name: 
// Module Name: tb_pe_overflow
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


module tb_pe_overflow;
    localparam DW_A  = 4;
    localparam DW_B  = 4;
    localparam ACC_W = 8;
    localparam PROD_W = DW_A + DW_B;

    logic clk;
    logic rst_n;
    logic acc_clear;

    logic signed [DW_A-1:0] a_in;
    logic a_valid_in;
    logic signed [DW_B-1:0] b_in;
    logic b_valid_in;

    logic signed [DW_A-1:0] a_out;
    logic a_out_valid;
    logic signed [DW_B-1:0] b_out;
    logic b_out_valid;

    logic signed [ACC_W-1:0] acc_out;
    logic acc_out_valid;
    logic overflow;

    // DUT
    pe_overflow #(
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
        .acc_out_valid(acc_out_valid),
        .overflow(overflow)
    );

    // 10 ns clock period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Reference model
    logic signed [ACC_W-1:0] model_acc;
    logic signed [PROD_W-1:0] pending_product;
    logic signed [DW_A-1:0] pending_a;
    logic signed [DW_B-1:0] pending_b;
    logic pending_valid;

    logic signed [ACC_W:0] model_sum;

    integer checks = 0;
    integer errors = 0;

    // One cycle of stimulus, followed by automatic checking.
    task automatic step(
        input logic signed [DW_A-1:0] a,
        input logic va,
        input logic signed [DW_B-1:0] b,
        input logic vb,
        input logic clear_acc
    );
        logic signed [ACC_W-1:0] expected_acc;
        logic expected_acc_valid;
        logic expected_overflow;

        logic signed [DW_A-1:0] expected_a;
        logic signed [DW_B-1:0] expected_b;
        logic expected_a_valid;
        logic expected_b_valid;

        logic signed [PROD_W-1:0] new_product;
        logic new_pending_valid;

        begin
            @(negedge clk);
            a_in       = a;
            a_valid_in = va;
            b_in       = b;
            b_valid_in = vb;
            acc_clear  = clear_acc;

            // Predict the DUT's Stage-1 behavior using the
            // transaction captured during the PREVIOUS cycle.
            @(posedge clk);

            expected_acc       = model_acc;
            expected_acc_valid = 1'b0;
            expected_overflow  = 1'b0;
            expected_a         = '0;
            expected_b         = '0;
            expected_a_valid   = 1'b0;
            expected_b_valid   = 1'b0;

            if (clear_acc) begin
                // Clear has priority over accumulation.
                expected_acc = '0;
            end
            else if (pending_valid) begin
                model_sum =
                    {model_acc[ACC_W-1], model_acc}
                    + {{(ACC_W+1-PROD_W){pending_product[PROD_W-1]}},
                       pending_product};

                expected_acc = model_sum[ACC_W-1:0];
                expected_acc_valid = 1'b1;

                // Signed overflow: extended result's top
                // two bits differ.
                expected_overflow =
                    model_sum[ACC_W] ^ model_sum[ACC_W-1];

                expected_a = pending_a;
                expected_b = pending_b;
                expected_a_valid = 1'b1;
                expected_b_valid = 1'b1;
            end

            // Prepare the next pending transaction from the
            // inputs sampled at THIS edge.
            new_pending_valid = va && vb;
            new_product = a * b;

            #1; // Allow nonblocking assignments to settle.

            checks = checks + 1;

            if (acc_out !== expected_acc) begin
                $error("ACC mismatch: got %0d, expected %0d",
                       $signed(acc_out), $signed(expected_acc));
                errors = errors + 1;
            end

            if (acc_out_valid !== expected_acc_valid) begin
                $error("acc_out_valid mismatch: got %b, expected %b",
                       acc_out_valid, expected_acc_valid);
                errors = errors + 1;
            end

            if (overflow !== expected_overflow) begin
                $error("Overflow mismatch: got %b, expected %b",
                       overflow, expected_overflow);
                errors = errors + 1;
            end

            if (a_out_valid !== expected_a_valid ||
                b_out_valid !== expected_b_valid) begin
                $error("Forwarding valid mismatch: A=%b B=%b",
                       a_out_valid, b_out_valid);
                errors = errors + 1;
            end

            if (a_out !== expected_a || b_out !== expected_b) begin
                $error("Forwarding data mismatch: A=%0d (expected %0d), B=%0d (expected %0d)",
                       $signed(a_out), $signed(expected_a),
                       $signed(b_out), $signed(expected_b));
                errors = errors + 1;
            end

            // Commit reference-model state.
            model_acc = expected_acc;

            // Clear suppresses the pending transaction in Stage 1,
            // but Stage 0 can still capture the current inputs.
            pending_valid = new_pending_valid;
            pending_a = a;
            pending_b = b;
            pending_product = new_product;

            $display(
                "Cycle check %0d: A=%0d B=%0d valid=%b%b clear=%b | ACC=%0d valid=%b overflow=%b",
                checks, $signed(a), $signed(b), va, vb, clear_acc,
                $signed(acc_out), acc_out_valid, overflow
            );
        end
    endtask

    initial begin
        rst_n = 1'b0;
        acc_clear = 1'b0;
        a_in = '0;
        b_in = '0;
        a_valid_in = 1'b0;
        b_valid_in = 1'b0;

        model_acc = '0;
        pending_product = '0;
        pending_a = '0;
        pending_b = '0;
        pending_valid = 1'b0;
        model_sum = '0;

        // Asynchronous reset
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // 1. Start from a known accumulator state.
        step(0, 1'b0, 0, 1'b0, 1'b1);
        step(0, 1'b0, 0, 1'b0, 1'b0);

        // 2. Basic positive and negative multiplication.
        step( 3, 1'b1,  2, 1'b1, 1'b0); // +6
        step(-3, 1'b1,  2, 1'b1, 1'b0); // -6
        step( 3, 1'b1, -2, 1'b1, 1'b0); // -6
        step(-3, 1'b1, -2, 1'b1, 1'b0); // +6
        step( 0, 1'b0,  0, 1'b0, 1'b0); // Drain pipeline

        // 3. Only one valid input: no product should be accepted.
        step( 5, 1'b1,  3, 1'b0, 1'b0);
        step( 5, 1'b0,  3, 1'b1, 1'b0);
        step( 0, 1'b0,  0, 1'b0, 1'b0);

        // 4. Accumulator clear and priority over a pending product.
        step( 4, 1'b1,  4, 1'b1, 1'b0);
        step( 2, 1'b1,  3, 1'b1, 1'b1); // Clear suppresses old product
        step( 0, 1'b0,  0, 1'b0, 1'b0); // Accumulate 2*3
        step( 0, 1'b0,  0, 1'b0, 1'b0);

        // 5. Positive signed overflow:
        // 7*7 = 49; three accumulated products = 147 > 127.
        step(0, 1'b0, 0, 1'b0, 1'b1);
        step(7, 1'b1, 7, 1'b1, 1'b0);
        step(7, 1'b1, 7, 1'b1, 1'b0);
        step(7, 1'b1, 7, 1'b1, 1'b0);
        step(0, 1'b0, 0, 1'b0, 1'b0); // Third product commits here
        step(0, 1'b0, 0, 1'b0, 1'b0); // Overflow must deassert

        // 6. Negative signed overflow:
        // -8*7 = -56; three products = -168 < -128.
        step(0, 1'b0, 0, 1'b0, 1'b1);
        step(-8, 1'b1, 7, 1'b1, 1'b0);
        step(-8, 1'b1, 7, 1'b1, 1'b0);
        step(-8, 1'b1, 7, 1'b1, 1'b0);
        step(0, 1'b0, 0, 1'b0, 1'b0);
        step(0, 1'b0, 0, 1'b0, 1'b0);

        // 7. Overflow recovery: clear, then normal accumulation.
        step(0, 1'b0, 0, 1'b0, 1'b1);
        step(2, 1'b1, 3, 1'b1, 1'b0);
        step(0, 1'b0, 0, 1'b0, 1'b0);
        step(0, 1'b0, 0, 1'b0, 1'b0);

        // 8. Back-to-back transactions and pipeline alignment.
        step(1, 1'b1, 2, 1'b1, 1'b0);
        step(2, 1'b1, 3, 1'b1, 1'b0);
        step(3, 1'b1, 4, 1'b1, 1'b0);
        step(0, 1'b0, 0, 1'b0, 1'b0);
        step(0, 1'b0, 0, 1'b0, 1'b0);

        if (errors == 0)
            $display("\nPASS: All %0d cycle checks passed.", checks);
        else
            $fatal(1, "\nFAIL: %0d errors across %0d cycle checks.",
                   errors, checks);

        $finish;
    end

endmodule

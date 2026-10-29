`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2026 09:39:00 AM
// Design Name: 
// Module Name: tb_pe
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

module pe_tb;

    // Testbench signals
    logic clk;
    logic rst_n;
    logic acc_clear;

    logic signed [7:0] a_in;
    logic a_valid_in;

    logic signed [7:0] b_in;
    logic b_valid_in;

    logic signed [7:0] a_out;
    logic a_out_valid;

    logic signed [7:0] b_out;
    logic b_out_valid;

    logic signed [31:0] acc_out;
    logic acc_out_valid;

    // Instantiate the PE
    pe #(
        .DW_a(8),
        .DW_b(8),
        .Acc_ip_width(32)
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

    // Clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        // Initialize inputs
        rst_n = 0;
        acc_clear = 0;
        a_in = 0;
        b_in = 0;
        a_valid_in = 0;
        b_valid_in = 0;

        // Hold reset, then release it
        repeat (2) @(negedge clk);
        rst_n = 1;

        // Test 1: 3 * 4 = 12
        @(negedge clk);
        a_in = 3;
        b_in = 4;
        a_valid_in = 1;
        b_valid_in = 1;

        // Test 2: 2 * 5 = 10; accumulated total should become 22
        @(negedge clk);
        a_in = 2;
        b_in = 5;

        // Test 3: Invalid input cycle; accumulator should hold
        @(negedge clk);
        a_valid_in = 0;
        b_valid_in = 0;
        a_in = 7;
        b_in = 6;

        // Test 4: Signed multiplication: -3 * 2 = -6
        @(negedge clk);
        a_in = -3;
        b_in = 2;
        a_valid_in = 1;
        b_valid_in = 1;

        // Test 5: Clear accumulator
        @(negedge clk);
        acc_clear = 0;
        a_valid_in = 0;
        b_valid_in = 0;

        @(negedge clk);
        acc_clear = 0;

        // Test 6: New accumulation after clear: 4 * 6 = 24
        @(negedge clk);
        a_in = 4;
        b_in = 6;
        a_valid_in = 1;
        b_valid_in = 1;

        @(negedge clk);
        a_valid_in = 0;
        b_valid_in = 0;

        // Allow pipeline to settle
        repeat (3) @(negedge clk);

        $finish;
    end

    // Display results after each rising edge
    always @(posedge clk) begin
        #1;
        $display(
            "time=%0t | A=%0d B=%0d | acc_clear=%b | acc_out=%0d | acc_valid=%b",
            $time, a_in, b_in, acc_clear, acc_out, acc_out_valid
        );
    end

endmodule


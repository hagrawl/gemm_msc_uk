`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/30/2026 11:30:41 PM
// Design Name: 
// Module Name: tb_sys_array_noforwarding
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




module tb_sys_array_noforwarding;


    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------

    localparam integer NR   = 2;
    localparam integer NC   = 2;
    localparam integer K    = 2;

    localparam integer DW_r = 8;
    localparam integer DW_c = 8;
    localparam integer ACCW = 32;

    localparam integer NUM_PE = NR * NC;

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------

    logic clk;
    logic rst_n;
    logic acc_clear;

    logic [DW_r*NR-1:0] row_data;
    logic [NR-1:0]      row_data_valid;

    logic [DW_c*NC-1:0] col_data;
    logic [NC-1:0]      col_data_valid;

    logic [(NR*NC*ACCW)-1:0] c_flat;
    logic [NR*NC-1:0]        c_valid_flat;

    // ------------------------------------------------------------
    // DUT instantiation
    // ------------------------------------------------------------

    systolic_array #(
        .NR   (NR),
        .NC   (NC),
        .DW_r (DW_r),
        .DW_c (DW_c),
        .ACCW (ACCW)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .acc_clear      (acc_clear),

        .row_data       (row_data),
        .row_data_valid (row_data_valid),

        .col_data       (col_data),
        .col_data_valid (col_data_valid),

        .c_flat         (c_flat),
        .c_valid_flat   (c_valid_flat)
    );

    // ------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // Test data
    //
    // A[transaction][row][k]
    // B[transaction][k][column]
    // ------------------------------------------------------------

    integer A [0:1][0:NR-1][0:K-1];
    integer B [0:1][0:K-1][0:NC-1];

    // Reference result:
    // C_ref[row][column]

    integer C_ref [0:NR-1][0:NC-1];

    // Number of output-valid pulses for each PE

    integer valid_count [0:NUM_PE-1];

    integer errors;

    // ------------------------------------------------------------
    // Monitor output-valid pulses
    // ------------------------------------------------------------

    integer monitor_pe;

    always @(posedge clk) begin
        #1;

        if (rst_n && !acc_clear) begin
            for (monitor_pe = 0; monitor_pe < NUM_PE;
                 monitor_pe = monitor_pe + 1) begin

                if (c_valid_flat[monitor_pe])
                    valid_count[monitor_pe] =
                        valid_count[monitor_pe] + 1;

            end
        end
    end

    // ------------------------------------------------------------
    // Reference model: clear expected results
    // ------------------------------------------------------------

    task automatic clear_reference;

        integer r, c;

        begin
            for (r = 0; r < NR; r = r + 1) begin
                for (c = 0; c < NC; c = c + 1) begin
                    C_ref[r][c] = 0;
                end
            end
        end

    endtask

    // ------------------------------------------------------------
    // Reference model: add one GEMM transaction
    //
    // C_ref += A x B
    // ------------------------------------------------------------

    task automatic add_reference;

        input integer transaction;

        integer r, c, k;
        integer product;

        begin
            for (r = 0; r < NR; r = r + 1) begin

                for (c = 0; c < NC; c = c + 1) begin

                    for (k = 0; k < K; k = k + 1) begin

                        product =
                            A[transaction][r][k] *
                            B[transaction][k][c];

                        C_ref[r][c] =
                            C_ref[r][c] + product;

                    end
                end
            end
        end

    endtask

    // ------------------------------------------------------------
    // Input launch offset
    //
    // Dense:
    //   k = 0 -> cycle 0
    //   k = 1 -> cycle 1
    //
    // Irregular:
    //   k = 0 -> cycle 0
    //   k = 1 -> cycle 2
    //
    // This guarantees an actual bubble for K=2.
    // ------------------------------------------------------------

    function automatic integer launch_offset;

        input integer index;
        input integer irregular;

        begin

            if (irregular)
                launch_offset = index * 2;
            else
                launch_offset = index;

        end

    endfunction

    // ------------------------------------------------------------
    // Calculate transaction span
    //
    // This determines how far apart consecutive GEMM transactions
    // are launched.
    // ------------------------------------------------------------

    function automatic integer transaction_span;

        input integer irregular;

        begin
            transaction_span =
                launch_offset(K-1, irregular) + 1;
        end

    endfunction

    // ------------------------------------------------------------
    // Drive GEMM transactions
    //
    // A movement:
    //   Row r starts at cycle 2*r.
    //
    // B movement:
    //   Column c starts at cycle 2*c.
    //
    // Each PE-to-PE forwarding hop takes two cycles in the
    // current PE implementation.
    // ------------------------------------------------------------

    task automatic drive_gemm;

        input integer number_of_transactions;
        input integer irregular;

        integer cycle;
        integer total_cycles;
        integer span;

        integer t, r, c, k;

        begin

            span = transaction_span(irregular);

            total_cycles =
                (number_of_transactions - 1) * span
                + span
                + 2 * (NR + NC);

            $display("");
            $display("----------------------------------------");
            $display("Driving %0d GEMM transaction(s)", 
                     number_of_transactions);
            $display("Irregular mode = %0d", irregular);
            $display("Transaction span = %0d", span);
            $display("----------------------------------------");

            for (cycle = 0; cycle < total_cycles;
                 cycle = cycle + 1) begin

                @(negedge clk);

                // Default: no valid input
                row_data       = '0;
                row_data_valid = '0;

                col_data       = '0;
                col_data_valid = '0;

                // ------------------------------------------------
                // Drive A operands
                // ------------------------------------------------

                for (t = 0; t < number_of_transactions;
                     t = t + 1) begin

                    for (r = 0; r < NR; r = r + 1) begin

                        for (k = 0; k < K; k = k + 1) begin

                            if (cycle ==
                                (t * span)
                                + (2 * r)
                                + launch_offset(k, irregular)) begin

                                row_data[r*DW_r +: DW_r] =
                                    A[t][r][k];

                                row_data_valid[r] = 1'b1;

                            end

                        end
                    end
                end

                // ------------------------------------------------
                // Drive B operands
                // ------------------------------------------------

                for (t = 0; t < number_of_transactions;
                     t = t + 1) begin

                    for (c = 0; c < NC; c = c + 1) begin

                        for (k = 0; k < K; k = k + 1) begin

                            if (cycle ==
                                (t * span)
                                + (2 * c)
                                + launch_offset(k, irregular)) begin

                                col_data[c*DW_c +: DW_c] =
                                    B[t][k][c];

                                col_data_valid[c] = 1'b1;

                            end

                        end
                    end
                end

                $display(
                    "Cycle %0d | row_valid=%b col_valid=%b",
                    cycle,
                    row_data_valid,
                    col_data_valid
                );

            end

            // ----------------------------------------------------
            // Stop driving inputs and allow the pipeline to drain
            // ----------------------------------------------------

            @(negedge clk);

            row_data       = '0;
            row_data_valid = '0;

            col_data       = '0;
            col_data_valid = '0;

            repeat (2 * (NR + NC) + 4)
                @(negedge clk);

        end

    endtask

    // ------------------------------------------------------------
    // Clear DUT and reference model
    // ------------------------------------------------------------

    task automatic clear_dut;

        integer p;

        begin

            @(negedge clk);

            acc_clear = 1'b1;

            @(negedge clk);

            acc_clear = 1'b0;

            clear_reference();

            for (p = 0; p < NUM_PE; p = p + 1)
                valid_count[p] = 0;

            // Allow the clear operation to settle
            repeat (2)
                @(negedge clk);

        end

    endtask

    // ------------------------------------------------------------
    // Check results and valid counts
    //
    // expected_valid_per_pe:
    //   K for one GEMM transaction
    //   2*K for two back-to-back transactions
    //   0 after accumulator clear
    // ------------------------------------------------------------

    task automatic check_results;

        input integer expected_valid_per_pe;

        integer r, c;
        integer pe_index;
        integer actual;

        begin

            $display("");
            $display("========================================");
            $display("Checking results");
            $display("========================================");

            for (r = 0; r < NR; r = r + 1) begin

                for (c = 0; c < NC; c = c + 1) begin

                    pe_index = r * NC + c;

                    actual = $signed(
                        c_flat[pe_index*ACCW +: ACCW]
                    );

                    $display(
                        "PE[%0d][%0d] : Expected = %0d, Actual = %0d",
                        r, c, C_ref[r][c], actual
                    );

                    if (actual !== C_ref[r][c]) begin

                        $display(
                            "ERROR: Result mismatch at PE[%0d][%0d]",
                            r, c
                        );

                        errors = errors + 1;

                    end

                    if (valid_count[pe_index] !=
                        expected_valid_per_pe) begin

                        $display(
                            "ERROR: Valid count mismatch at PE[%0d][%0d]. Expected=%0d Actual=%0d",
                            r, c,
                            expected_valid_per_pe,
                            valid_count[pe_index]
                        );

                        errors = errors + 1;

                    end
                    else begin

                        $display(
                            "PE[%0d][%0d] valid count PASS (%0d)",
                            r, c, valid_count[pe_index]
                        );

                    end

                end
            end

            $display("========================================");

        end

    endtask

    // ------------------------------------------------------------
    // Initialize test data
    // ------------------------------------------------------------

    task automatic initialize_test_data;

        begin

            // Transaction 0

            A[0][0][0] = -3;
            A[0][0][1] = -1;

            A[0][1][0] =  0;
            A[0][1][1] =  2;

            B[0][0][0] = -1;
            B[0][0][1] =  2;

            B[0][1][0] =  1;
            B[0][1][1] = -3;

            // Transaction 1

            A[1][0][0] =  1;
            A[1][0][1] =  2;

            A[1][1][0] = -2;
            A[1][1][1] =  1;

            B[1][0][0] = -2;
            B[1][0][1] =  1;

            B[1][1][0] =  1;
            B[1][1][1] = -2;

        end

    endtask

    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------

    integer i;

    initial begin

        // Initial values

        rst_n          = 1'b0;
        acc_clear      = 1'b0;

        row_data       = '0;
        row_data_valid = '0;

        col_data       = '0;
        col_data_valid = '0;

        errors = 0;

        clear_reference();

        for (i = 0; i < NUM_PE; i = i + 1)
            valid_count[i] = 0;

        initialize_test_data();

        $display("");
        $display("========================================");
        $display("SYSTOLIC ARRAY GEMM TESTBENCH");
        $display("NR=%0d NC=%0d K=%0d", NR, NC, K);
        $display("========================================");

        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        repeat (3)
            @(negedge clk);

        rst_n = 1'b1;

        repeat (2)
            @(negedge clk);

        // ========================================================
        // TEST 1: Signed GEMM
        // ========================================================

        $display("");
        $display("TEST 1: Signed GEMM");

        clear_dut();

        add_reference(0);

        drive_gemm(1, 0);

        check_results(K);

        // ========================================================
        // TEST 2: Back-to-back GEMM transactions
        // ========================================================

        $display("");
        $display("TEST 2: Back-to-back GEMM transactions");

        clear_dut();

        // IMPORTANT:
        // Both transactions contribute to the expected result.
        // The DUT accumulator is not cleared between transactions.

        add_reference(0);
        add_reference(1);

        drive_gemm(2, 0);

        check_results(2*K);

        // ========================================================
        // TEST 3: Irregular valid pattern
        // ========================================================

        $display("");
        $display("TEST 3: Irregular valid pattern");

        clear_dut();

        add_reference(0);

        // irregular = 1 inserts a bubble between K operands
        drive_gemm(1, 1);

        check_results(K);

        // ========================================================
        // TEST 4: Accumulator clear
        // ========================================================

        $display("");
        $display("TEST 4: Accumulator clear");

        clear_dut();

        // clear_dut() also clears the reference model and
        // resets the valid counters.

        check_results(0);

        // --------------------------------------------------------
        // Final status
        // --------------------------------------------------------

        $display("");
        $display("========================================");

        if (errors == 0) begin
            $display("ALL TESTS PASSED");
        end
        else begin
            $display("TESTBENCH FAILED: %0d error(s)", errors);
        end

        $display("========================================");

        $finish;

    end

endmodule

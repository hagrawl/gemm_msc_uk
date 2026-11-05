`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/01/2026 04:16:38 PM
// Design Name: 
// Module Name: controller_preload
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
// This controller only works for  a square matrix, for a rectangular matrix it'll fail.
//////////////////////////////////////////////////////////////////////////////////




`timescale 1ns / 1ps

module controller_preload #(
    parameter int NR_A  = 3,
    parameter int NR_B  = 3,
    parameter int NC_A  = 3,
    parameter int NC_B  = 3,
    parameter int MODE_A = 0,
    parameter int MODE_B = 1,
    parameter int DW = 8
)(
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------
    // A memory interface
    // ------------------------------------------------
    output logic rd_req_A,
    input  logic rd_req_ready_A,

    input  logic [DW*NC_A-1:0] data_A,
    input  logic rd_done_A,
    input  logic rd_valid_A,
    output logic rd_ready_A,

    // ------------------------------------------------
    // B memory interface
    // ------------------------------------------------
    output logic rd_req_B,
    input  logic rd_req_ready_B,

    input  logic [DW*NR_B-1:0] data_B,
    input  logic rd_done_B,
    input  logic rd_valid_B,
    output logic rd_ready_B,

    // ------------------------------------------------
    // A/B wavefront outputs
    // ------------------------------------------------
    output logic [DW*NR_A-1:0] data_A_out,
    output logic [NR_A-1:0]    data_A_vld,

    output logic [DW*NC_B-1:0] data_B_out,
    output logic [NC_B-1:0]    data_B_vld,

    // ------------------------------------------------
    // Controller interface
    // ------------------------------------------------
    input  logic start,
    output logic busy,
    output logic done
);

    // ====================================================
    // 1. FSM DECLARATIONS
    // ====================================================

    typedef enum logic [1:0] {
        Idle,
        Fetch,
        Delivery
    } state_type;

    state_type state_reg, state_nxt;


    // ====================================================
    // 2. MEMORY DECLARATIONS
    // ====================================================

    // A is stored row-wise.
    logic [DW*NC_A-1:0] A_mem [0:NR_A-1];

    // B is stored column-wise.
    logic [DW*NR_B-1:0] B_mem [0:NC_B-1];


    // ====================================================
    // 3. WRITE POINTERS AND RESPONSE COUNTERS
    // ====================================================

    localparam int A_PTR_W =
        (NR_A <= 1) ? 1 : $clog2(NR_A);

    localparam int B_PTR_W =
        (NC_B <= 1) ? 1 : $clog2(NC_B);

    logic [A_PTR_W-1:0] A_wr_ptr;
    logic [B_PTR_W-1:0] B_wr_ptr;

    localparam int A_CNT_W = $clog2(NR_A+1);
    localparam int B_CNT_W = $clog2(NC_B+1);

    logic [A_CNT_W-1:0] A_received;
    logic [B_CNT_W-1:0] B_received;


    // ====================================================
    // 4. DELIVERY COUNTER AND WAVEFRONT SIGNALS
    // ====================================================

    // Number of wavefront delivery cycles:
    // K + max(M,N) - 1
//This variable is aligned to check, lets sppose for any mxk and kxn matrix, how many cycle it would take to do complete pe ops, if we gave data to pe in diagonal manner
// a00, a01 a10,  a02 a11 a20..
    localparam int DELIVERY_CYCLES =
        NC_A + ((NR_A > NC_B) ? NR_A : NC_B) - 1;

    localparam int RD_CNTR_WIDTH =
        (DELIVERY_CYCLES <= 1) ?
        1 : $clog2(DELIVERY_CYCLES);

    logic [RD_CNTR_WIDTH-1:0] rd_cntr;

    logic compute_done;

    // A: one lane per row
    logic [DW*NR_A-1:0] A_data_next;
    logic [NR_A-1:0]    A_valid_next;

    // B: one lane per column
    logic [DW*NC_B-1:0] B_data_next;
    logic [NC_B-1:0]    B_valid_next;

    integer i;
    integer j;


    // ====================================================
    // 5. FSM SEQUENTIAL BLOCK
    // ====================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n)
            state_reg <= Idle;

        else
            state_reg <= state_nxt;

    end


    // ====================================================
    // 6. FSM COMBINATIONAL BLOCK
    // ====================================================

    always_comb begin

        // Default assignments
        state_nxt = state_reg;

        rd_req_A = 1'b0;
        rd_req_B = 1'b0;

        rd_ready_A = 1'b0;
        rd_ready_B = 1'b0;

        busy = 1'b0;
        done = compute_done;

        case (state_reg)

            // --------------------------------------------
            // IDLE
            // --------------------------------------------

            Idle: begin

                rd_req_A = 1'b1;
                rd_req_B = 1'b1;

                if (start &&
                    rd_req_ready_A &&
                    rd_req_ready_B) begin

                    state_nxt = Fetch;

                end

            end


            // --------------------------------------------
            // FETCH
            // --------------------------------------------

            Fetch: begin

                busy = 1'b1;

            if (A_received < NR_A)
                rd_req_A = 1'b1;
            else
                rd_req_A = 1'b0;

            if (B_received < NC_B)
                rd_req_B = 1'b1;
            else
                rd_req_B = 1'b0;      

                rd_ready_A = 1'b1;
                rd_ready_B = 1'b1;

                if ((A_received == NR_A) &&
                    (B_received == NC_B)) begin

                    state_nxt = Delivery;

                end

            end


            // --------------------------------------------
            // DELIVERY
            // --------------------------------------------

            Delivery: begin

                busy = 1'b1;

                // Exit on the final delivery cycle.
                if (rd_cntr == DELIVERY_CYCLES-1) begin

                    state_nxt = Idle;

                end

            end


            default: begin

                state_nxt = Idle;

            end

        endcase

    end


    // ====================================================
    // 7. MEMORY WRITE SEQUENTIAL BLOCK
    // ====================================================

    always_ff @(posedge clk or negedge rst_n) 
        begin

        if (!rst_n) 
        begin

            A_wr_ptr <= '0;
            B_wr_ptr <= '0;

            A_received <= '0;
            B_received <= '0;

        end

        else 
        begin

            // --------------------------------------------
            // Store A rows
            // --------------------------------------------

            if (state_reg == Fetch &&
                rd_valid_A &&
                rd_ready_A) begin

                A_mem[A_wr_ptr] <= data_A;

                A_received <= A_received + 1'b1;

                if (A_wr_ptr == NR_A-1)
                    A_wr_ptr <= '0;

                else
                    A_wr_ptr <= A_wr_ptr + 1'b1;

            end


            // --------------------------------------------
            // Store B columns
            // --------------------------------------------

            if (state_reg == Fetch && rd_valid_B && rd_ready_B) 
            begin
                B_mem[B_wr_ptr] <= data_B;
                B_received <= B_received + 1'b1;
                if (B_wr_ptr == NC_B-1)
                    B_wr_ptr <= '0;
                else
                    B_wr_ptr <= B_wr_ptr + 1'b1;
            end


            // --------------------------------------------
            // Prepare for next tile after completion
            // --------------------------------------------

            if (compute_done) begin

                A_wr_ptr <= '0;
                B_wr_ptr <= '0;

                A_received <= '0;
                B_received <= '0;

            end

        end

       end
    


    // ====================================================
    // 8. A/B WAVEFRONT COMBINATIONAL BLOCK
    // ====================================================

    always_comb 
    begin

        // Default assignments
        A_data_next  = '0;
        A_valid_next = '0;

        B_data_next  = '0;
        B_valid_next = '0;


        if (state_reg == Delivery) 
        begin

            // --------------------------------------------
            // A wavefront
            // --------------------------------------------

            for (i = 0; i < NR_A; i = i + 1) 
            begin
                if ((rd_cntr >= i) &&((rd_cntr - i) < NC_A)) 
                    begin
                    A_data_next[i*DW +: DW] = A_mem[i][(rd_cntr-i)*DW +: DW];
                    A_valid_next[i] = 1'b1;
                    end

                end

            end


            // --------------------------------------------
            // B wavefront
            // --------------------------------------------
   
            for (j = 0; j < NC_B; j = j + 1) 
            begin
                if ((rd_cntr >= j) &&((rd_cntr - j) < NR_B)) 
                    begin
                        B_data_next[j*DW +: DW] =B_mem[j][(rd_cntr-j)*DW +: DW];
                        B_valid_next[j] = 1'b1;
                    end
            end
        end

    // ====================================================
    // 9. DELIVERY SEQUENTIAL BLOCK
    // ====================================================

    always_ff @(posedge clk or negedge rst_n) 
       begin
        if (!rst_n) 
         begin
            rd_cntr <= '0;
            data_A_out <= '0;
            data_A_vld <= '0;
            data_B_out <= '0;
            data_B_vld <= '0;
            compute_done <= 1'b0;
         end
        else 
         begin

            // Default: completion is a one-cycle pulse.
            compute_done <= 1'b0;
            if (state_reg == Delivery) begin

                // Register selected A wavefront
                data_A_out <= A_data_next;
                data_A_vld <= A_valid_next;
                // Register selected B wavefront
                data_B_out <= B_data_next;
                data_B_vld <= B_valid_next;
                // ----------------------------------------
                // Increment delivery counter
                // ----------------------------------------
                if (rd_cntr < DELIVERY_CYCLES-1) 
                begin
                    rd_cntr <= rd_cntr + 1'b1;
                end
                else 
                begin
                    rd_cntr <= '0;
                    compute_done <= 1'b1;
                end
            end 
            else 
                begin
                rd_cntr <= '0;
                data_A_out <= '0;
                data_A_vld <= '0;

                data_B_out <= '0;
                data_B_vld <= '0;
                end
         end
       end

endmodule

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2026 02:02:19 PM
// Design Name: 
// Module Name: io_buffer_ping_pong
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


module io_buffer_ping_pong #(
    parameter int DW   = 8,
    parameter int MODE = 0,       // 0: row-wise, 1: column-wise
    parameter int NR   = 4,
    parameter int NC   = 4,

    parameter int TOTAL_ELEMS = NR * NC,
    parameter int RD_WIDTH    = (MODE == 0) ? NC : NR,
    parameter int RD_COUNT    = (MODE == 0) ? NR : NC,

    parameter int WR_COUNT_W =
        (TOTAL_ELEMS <= 1) ? 1 : $clog2(TOTAL_ELEMS),

    parameter int RD_COUNT_W =
        (RD_COUNT <= 1) ? 1 : $clog2(RD_COUNT)
)(
    input  logic clk,
    input  logic rst_n,

    // Write interface
    input  logic          wr_valid,
    output logic          wr_ready,
    input  logic [DW-1:0] wr_data,
    output logic          load_done,

    // Read request interface
    input  logic rd_en,
    output logic rd_req_ready,

    // Read response interface
    output logic                    rd_valid,
    input  logic                    rd_ready,
    output logic                    rd_done,
    output logic [DW*RD_WIDTH-1:0]  rd_data
);

    // ------------------------------------------------
    // 1. Memory banks
    // ------------------------------------------------

    logic [DW-1:0] bank0_data [0:TOTAL_ELEMS-1];
    logic [DW-1:0] bank1_data [0:TOTAL_ELEMS-1];


    // ------------------------------------------------
    // 2. Bank states
    // ------------------------------------------------

    typedef enum logic [1:0] {
        EMPTY,
        FILLING,
        FULL,
        READING
    } bank_state_type;

    bank_state_type bank_state [0:1];

    logic write_bank_sel;
    logic read_bank_sel;

    logic write_active;
    logic read_active;


    // ------------------------------------------------
    // 3. Counters
    // ------------------------------------------------

    logic [WR_COUNT_W-1:0] write_cntr;
    logic [RD_COUNT_W-1:0] read_cntr;


    // ------------------------------------------------
    // 4. Handshake signals
    // ------------------------------------------------

    logic wr_fire;
    logic rd_fire;

    logic output_slot_available;

    logic wr_last;
    logic rd_last;

    assign wr_ready = write_active;

    assign output_slot_available = !rd_valid || rd_ready;

    assign rd_req_ready = read_active && output_slot_available;

    assign wr_fire = wr_valid && wr_ready;

    assign rd_fire = rd_en && rd_req_ready;

    assign wr_last = (write_cntr == TOTAL_ELEMS - 1);

    assign rd_last = (read_cntr == RD_COUNT - 1);


    // ------------------------------------------------
    // 5. Memory write logic
    // ------------------------------------------------
    // Memory is intentionally not reset.
    // Only the selected FILLING bank can be written.

    always_ff @(posedge clk) begin
        if (wr_fire) begin

            if (write_bank_sel == 1'b0)
                bank0_data[write_cntr] <= wr_data;
            else
                bank1_data[write_cntr] <= wr_data;

        end
    end


    // ------------------------------------------------
    // 6. Write counter and load_done
    // ------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_cntr <= '0;
        end
        else if (wr_fire) begin

            if (wr_last)
                write_cntr <= '0;
            else
                write_cntr <= write_cntr + 1'b1;

        end
    end


    // ------------------------------------------------
    // 7. Read logic
    // ------------------------------------------------
    // One complete row or column is returned per
    // accepted read request.
    //
    // rd_data[i*DW +: DW] contains element i.
    //
    // MODE 0:
    //   address = row_index * NC + column_index
    //
    // MODE 1:
    //   address = row_index * NC + column_index
    //   with row_index varying for each output element.

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_cntr <= '0;
            rd_data   <= '0;
            rd_valid  <= 1'b0;
            rd_done   <= 1'b0;
        end
        else begin

            // Default: one-cycle completion pulse
            rd_done <= 1'b0;

            // Consume an existing output vector
            if (rd_valid && rd_ready)
                rd_valid <= 1'b0;

            if (rd_fire) begin

                for (int i = 0; i < RD_WIDTH; i++) begin

                    if (MODE == 0) begin

                        // Row-wise read
                        if (read_bank_sel == 1'b0)
                            rd_data[i*DW +: DW] <=
                                bank0_data[read_cntr*NC + i];
                        else
                            rd_data[i*DW +: DW] <=
                                bank1_data[read_cntr*NC + i];

                    end
                    else begin

                        // Column-wise read
                        if (read_bank_sel == 1'b0)
                            rd_data[i*DW +: DW] <=
                                bank0_data[i*NC + read_cntr];
                        else
                            rd_data[i*DW +: DW] <=
                                bank1_data[i*NC + read_cntr];

                    end

                end

                rd_valid <= 1'b1;

                if (rd_last) begin
                    read_cntr <= '0;
                    rd_done   <= 1'b1;
                end
                else begin
                    read_cntr <= read_cntr + 1'b1;
                end

            end

        end
    end


    // ------------------------------------------------
    // 8. Bank control logic
    // ------------------------------------------------
    // Writer selects EMPTY banks.
    // Reader selects FULL banks.
    // Writer and reader operate independently.

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            bank_state[0] <= FILLING;
            bank_state[1] <= EMPTY;

            write_bank_sel <= 1'b0;
            read_bank_sel  <= 1'b0;

            write_active <= 1'b1;
            read_active  <= 1'b0;

            load_done <= 1'b0;

        end
        else begin

            // Default: one-cycle completion pulse
            load_done <= 1'b0;


            // ----------------------------------------
            // WRITE BANK CONTROL
            // ----------------------------------------

            if (wr_fire && wr_last) begin

                // Current bank has received a full tile
                bank_state[write_bank_sel] <= FULL;

                write_active <= 1'b0;
                load_done    <= 1'b1;

            end
            else if (!write_active) begin

                // Look for an EMPTY bank
                if (bank_state[0] == EMPTY) begin

                    bank_state[0] <= FILLING;
                    write_bank_sel <= 1'b0;
                    write_active <= 1'b1;

                end
                else if (bank_state[1] == EMPTY) begin

                    bank_state[1] <= FILLING;
                    write_bank_sel <= 1'b1;
                    write_active <= 1'b1;

                end

            end


            // ----------------------------------------
            // READ BANK CONTROL
            // ----------------------------------------

            if (rd_fire && rd_last) begin

                // Final vector has been copied into
                // the registered output interface.
                bank_state[read_bank_sel] <= EMPTY;

                read_active <= 1'b0;

            end
            else if (!read_active) begin

                // Look for a FULL bank
                if (bank_state[0] == FULL) begin

                    bank_state[0] <= READING;
                    read_bank_sel <= 1'b0;
                    read_active <= 1'b1;

                end
                else if (bank_state[1] == FULL) begin

                    bank_state[1] <= READING;
                    read_bank_sel <= 1'b1;
                    read_active <= 1'b1;

                end

            end

        end
    end

endmodule

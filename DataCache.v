`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2017/12/17 16:22:55
// Design Name:
// Module Name: DataCache
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

`include "defines.v"

module fifo_buffer #(
    parameter ENTRY = 8,
    parameter ENTRY_WIDTH = 3
) (
    input clk,
    input rst,

    output empty,
    output full,

    input in_valid,
    input [`Addr_Width-1 : 0] fifo_in_addr,
    input [`Data_Width-1 : 0] fifo_in_data,
    input [3             : 0] fifo_in_mask,

    input out_valid,
    output [`Addr_Width-1 : 0] fifo_out_addr,
    output [`Data_Width-1 : 0] fifo_out_data,
    input [3              : 0] fifo_out_mask,

    input [`Addr_Width-1 : 0] check_addr,
    output reg [`Data_Width-1 : 0] check_data,
    output reg check_same
);
    reg valid_array[ENTRY-1 : 0];
    reg [`Addr_Width-1 : 0] addr_array[ENTRY-1:0];
    reg [`Data_Width-1 : 0] data_array[ENTRY-1:0];
    reg [3             : 0] mask_array[ENTRY-1:0];
    reg [ENTRY_WIDTH-1 : 0] in_ptr, out_ptr, counter;

    assign full = (counter == ENTRY);
    assign empty = (counter == 0 && !in_valid);
    assign fifo_out_addr = counter ? addr_array[out_ptr] : fifo_in_addr;
    assign fifo_out_data = counter ? data_array[out_ptr] : fifo_in_data;
    assign fifo_out_mask = counter ? mask_array[out_ptr] : fifo_in_mask;

    reg in_same;

    integer i;
    always @ (*) begin
        in_same <= 0;
        for (i = 0; i < ENTRY; i = i + 1) begin
            if (valid_array[i] && fifo_in_addr == addr_array[i]) begin
                in_same <= 1;
                data_array[i][7:0] <= fifo_in_mask[0] ? fifo_in_data[7:0] : data_array[i][7:0];
                data_array[i][15:8] <= fifo_in_mask[1] ? fifo_in_data[15:8] : data_array[i][15:8];
                data_array[i][23:16] <= fifo_in_mask[2] ? fifo_in_data[23:16] : data_array[i][23:16];
                data_array[i][31:24] <= fifo_in_mask[3] ? fifo_in_data[31:24] : data_array[i][31:24];
            end
        end
    end

    always @ (posedge clk) begin
        if (rst) begin
            in_ptr <= 0;
            out_ptr <= 0;
            counter <= 0;
            for (i = 0; i < ENTRY; i = i + 1) valid_array[i] <= 0;
        end else begin
            case ({out_valid, in_valid})
                2'b01: begin
                    if (!in_same) begin
                        in_ptr <= in_ptr + 1;
                        valid_array[in_ptr] <= 1;
                        mask_array[in_ptr] <= fifo_in_mask;
                        addr_array[in_ptr] <= fifo_in_addr;
                        data_array[in_ptr] <= fifo_in_data;
                        counter <= counter + 1;
                    end
                end
                2'b10: begin
                    valid_array[out_ptr] <= 0;
                    out_ptr <= out_ptr + 1;
                    counter <= counter - 1;
                end
                2'b11: begin
                    if (counter) begin
                        if (!in_same) begin
                            in_ptr <= in_ptr + 1;
                            valid_array[in_ptr] <= 1;
                            mask_array[in_ptr] <= fifo_in_mask;
                            addr_array[in_ptr] <= fifo_in_addr;
                            data_array[in_ptr] <= fifo_in_data;
                        end
                        valid_array[out_ptr] <= 0;
                        out_ptr <= out_ptr + 1;
                    end
                end
            endcase
        end
    end

    always @ (*) begin
        check_same <= 0;
        for (i = 0; i < ENTRY; i = i + 1) begin
            if (valid_array[i] && addr_array[i] == check_addr) begin
                check_same <= 1;
                check_data <= data_array[i];
            end
        end
    end

endmodule

module CacheWay #(
    parameter TAG_WIDTH = 19,
    parameter INDEX_WIDTH = 7,
    parameter BLOCK_OFFSET_WIDTH = 6,
    parameter BLOCK_SIZE = (1 << BLOCK_OFFSET_WIDTH)
) (
    input clk,
    input modify,
    input [INDEX_WIDTH-1:0] read_index,
    input [BLOCK_OFFSET_WIDTH-1:0] read_blockoffset,
    input [INDEX_WIDTH-1:0] modify_index,
    input [BLOCK_OFFSET_WIDTH-1:0] modify_blockoffset,
    input [3:0] i_mask,
    input [`Data_Width-1:0] i_data,
    output [`Data_Width-1:0] o_data
);
    reg [`Data_Width-1:0] data_array[(1<<INDEX_WIDTH)-1:0][(BLOCK_SIZE>>2)-1:0];
    always @ (posedge clk) begin
        if (modify) begin
            if (i_mask[0]) data_array[modify_index][modify_blockoffset>>2][7:0] <= i_data[7:0];
            if (i_mask[1]) data_array[modify_index][modify_blockoffset>>2][15:8] <= i_data[15:8];
            if (i_mask[2]) data_array[modify_index][modify_blockoffset>>2][23:16] <= i_data[23:16];
            if (i_mask[3]) data_array[modify_index][modify_blockoffset>>2][31:24] <= i_data[31:24];
        end
    end
    assign o_data = (read_index == modify_index && (read_blockoffset>>2) == (modify_blockoffset>>2) ? i_data :
                            data_array[read_index][read_blockoffset>>2]);
endmodule

module DataCache #(
    parameter TAG_WIDTH = 19,
    parameter INDEX_WIDTH = 7,
    parameter BLOCK_OFFSET_WIDTH = 6,
    parameter BLOCK_SIZE = (1 << BLOCK_OFFSET_WIDTH),
    parameter ASSOCIATIVITY = 2
) (
    input clk,
    input rst,
    // with LoadStore
    input prefetch,
    input [`Addr_Width-1 : 0]  pre_addr,
    input read,
    input [`Addr_Width-1 : 0] read_addr,
    output reg read_done,
    output reg [`Data_Width-1 : 0] read_data,
    // with ROB
    input write,
    input [`Addr_Width-1 : 0] write_addr,
    input [`Data_Width-1 : 0] write_data,
    input [3             : 0] write_mask,
    output reg write_done,
    // with Memory
    input mem_free,
    input mem_read_valid,
    input [`Data_Width-1:0] mem_i_data,
    output reg [1:0] mem_rw_flag,
    output reg [`Addr_Width-1:0] mem_addr,
    output reg [`Data_Width-1:0] mem_o_data,
    output reg [3:0] mem_o_mask
);
    localparam  STATE_WIDTH = 2;
    localparam  STATE_READY = 2'd0;
    localparam  STATE_READ_C = 2'd1;
    localparam  STATE_READ_N = 2'd2;
    localparam  STATE_WRITE = 2'd3;
    localparam  READ = 2'b10;
    localparam  WRITE = 2'b01;

    reg [TAG_WIDTH-1:0] tag_array[(1<<INDEX_WIDTH)-1:0][ASSOCIATIVITY-1:0];
    reg valid_array[(1<<INDEX_WIDTH)-1:0][ASSOCIATIVITY-1:0];
    reg ctrl_array[(1<<INDEX_WIDTH)-1:0][ASSOCIATIVITY-1:0];

    reg [TAG_WIDTH-1:0] i_tag, r_i_tag, pre_o_tag;
    reg [INDEX_WIDTH-1:0] i_index, r_i_index, pre_o_index;
    reg [BLOCK_OFFSET_WIDTH-1:0] i_blockoffset, r_i_blockoffset, pre_o_blockoffset, gen_blockoffset;
    reg location, r_location, pre_location;

    reg way0_modify, way1_modify;
    reg [INDEX_WIDTH-1:0] way0_read_index, way1_read_index;
    reg [INDEX_WIDTH-1:0] way0_modify_index, way1_modify_index;
    reg [BLOCK_OFFSET_WIDTH-1:0] way0_read_blockoffset, way1_read_blockoffset;
    reg [BLOCK_OFFSET_WIDTH-1:0] way0_modify_blockoffset, way1_modify_blockoffset;
    reg [`Data_Width-1:0] way0_i_data, way1_i_data;
    wire [`Data_Width-1:0] way0_o_data, way1_o_data;
    reg [3:0] way0_mask, way1_mask;

    reg [STATE_WIDTH-1 : 0] state, next_state;

    reg pre_i_valid, pre_o_valid;
    wire pre_full, pre_empty;
    reg [`Addr_Width-1:0] pre_i_addr;
    wire [`Addr_Width-1:0] pre_o_addr;
    reg [`Data_Width-1:0] pre_i_data;
    wire [`Data_Width-1:0] pre_o_data;
    reg wb_i_valid, wb_o_valid;
    wire wb_full, wb_empty, wb_check_same;
    reg [`Addr_Width-1:0] wb_i_addr, wb_check_addr;
    wire [`Addr_Width-1:0] wb_o_addr;
    reg [`Data_Width-1:0] wb_i_data;
    wire [`Data_Width-1:0] wb_o_data, wb_check_data;
    reg [3:0] wb_i_mask, wb_o_mask;

    fifo_buffer prefetch_buffer (
        .clk (clk),
        .rst (rst),

        .empty (pre_empty),
        .full (pre_full),

        .in_valid (pre_i_valid),
        .fifo_in_addr (pre_i_addr),
        .fifo_in_data (pre_i_data),

        .out_valid (pre_o_valid),
        .fifo_out_addr (pre_o_addr),
        .fifo_out_data (pre_o_data)
    );

    fifo_buffer write_buffer (
        .clk (clk),
        .rst (rst),

        .empty (wb_empty),
        .full (wb_full),

        .in_valid (wb_i_valid),
        .fifo_in_addr (wb_i_addr),
        .fifo_in_data (wb_i_data),
        .fifo_in_mask (wb_i_mask),

        .out_valid (wb_o_valid),
        .fifo_out_addr (wb_o_addr),
        .fifo_out_data (wb_o_data),
        .fifo_out_mask (wb_o_mask),

        .check_addr (wb_check_addr),
        .check_data (wb_check_data),
        .check_same (wb_check_same)
    );

    CacheWay cache_way0 (
        .clk (clk),
        .modify (way0_modify),
        .read_index (way0_read_index),
        .read_blockoffset (way0_read_blockoffset),
        .modify_index (way0_modify_index),
        .modify_blockoffset (way0_modify_blockoffset),
        .i_mask (way0_mask),
        .i_data (way0_i_data),
        .o_data (way0_o_data)
    );

    CacheWay cache_way1 (
        .clk (clk),
        .modify (way1_modify),
        .read_index (way1_read_index),
        .read_blockoffset (way1_read_blockoffset),
        .modify_index (way1_modify_index),
        .modify_blockoffset (way1_modify_blockoffset),
        .i_mask (way1_mask),
        .i_data (way1_i_data),
        .o_data (way1_o_data)
    );

    always @ (*) begin
        case (1'b1)
            read: begin
                i_tag <= read_addr[BLOCK_OFFSET_WIDTH+INDEX_WIDTH+TAG_WIDTH-1:BLOCK_OFFSET_WIDTH+INDEX_WIDTH];
                i_index <= read_addr[BLOCK_OFFSET_WIDTH+INDEX_WIDTH-1:BLOCK_OFFSET_WIDTH];
                i_blockoffset <= read_addr[BLOCK_OFFSET_WIDTH-1:0];
            end
            write: begin
                i_tag <= write_addr[BLOCK_OFFSET_WIDTH+INDEX_WIDTH+TAG_WIDTH-1:BLOCK_OFFSET_WIDTH+INDEX_WIDTH];
                i_index <= write_addr[BLOCK_OFFSET_WIDTH+INDEX_WIDTH-1:BLOCK_OFFSET_WIDTH];
                i_blockoffset <= write_addr[BLOCK_OFFSET_WIDTH-1:0];
            end
            default : ;
        endcase
        if (prefetch) begin
            pre_o_tag <= pre_o_addr[BLOCK_OFFSET_WIDTH+INDEX_WIDTH+TAG_WIDTH-1:BLOCK_OFFSET_WIDTH+INDEX_WIDTH];
            pre_o_index <= pre_o_addr[BLOCK_OFFSET_WIDTH+INDEX_WIDTH-1:BLOCK_OFFSET_WIDTH];
            pre_o_blockoffset <= pre_o_addr[BLOCK_OFFSET_WIDTH-1:0];
        end
    end

    always @ (*) begin
        case ({1'b1, i_tag})
            {valid_array[i_index][0], tag_array[i_index][0]}: begin
                location <= 0;
            end
            {valid_array[i_index][1], tag_array[i_index][1]}: begin
                location <= 1;
            end
            default: begin
                location <= ctrl_array[i_index][0] ? 1 : 0;
            end
        endcase
        case ({1'b1, pre_o_tag})
            {valid_array[pre_o_index][0], tag_array[pre_o_index][0]}: begin
                pre_location <= 0;
            end
            {valid_array[pre_o_index][1], tag_array[pre_o_index][1]}: begin
                pre_location <= 1;
            end
            default: begin
                pre_location <= 0;
            end
        endcase
    end

    always @ (*) begin
        wb_check_addr <= read_addr;
    end

    always @ (*) begin
        next_state <= state;
        read_done <= 0;
        write_done <= 0;
        way0_modify <= 0;
        way1_modify <= 0;
        way0_read_index <= i_index;
        way1_read_index <= i_index;
        way0_read_blockoffset <= i_blockoffset;
        way1_read_blockoffset <= i_blockoffset;
        wb_i_valid <= 0;
        wb_o_valid <= 0;
        pre_i_valid <= 0;
        pre_o_valid <= 0;
        if (read && write) $display ("Read and write are both valid.\n");
        if (read && prefetch) $display ("Read and prefetch are both valid.\n");
        if (write && prefetch) $display ("write and prefetch are both valid.\n");
        if (read) begin
            if (valid_array[i_index][location] && tag_array[i_index][location] == i_tag) begin
            $display ("fatal error0!");
                read_done <= 1;
                case (location)
                    0: read_data <= way0_o_data;
                    1: read_data <= way1_o_data;
                endcase
            end else if (wb_check_same) begin
                read_done <= 1;
                read_data <= wb_check_data;
            end
        end
        if (write) begin
            if (valid_array[i_index][location] && tag_array[i_index][location] == i_tag) begin
                case (location)
                    0: begin
                        way0_modify <= 1;
                        way0_i_data <= write_data;
                        way0_mask <= write_mask;
                    end
                    1: begin
                        way1_modify <= 1;
                        way1_i_data <= write_data;
                        way1_mask <= write_mask;
                    end
                endcase
            end
            if (!wb_full) begin
                write_done <= 1;
                wb_i_valid <= 1;
                wb_i_addr <= write_addr;
                wb_i_data <= write_data;
            end
        end
        case (state)
            STATE_READY: begin
                $display ("fatal error1!");
                case (1'b1)
                    read: begin
                        if (!(valid_array[i_index][location] && tag_array[i_index][location] == i_tag)) begin
                            read_done <= 0;
                            next_state <= STATE_READ_C;
                            r_i_tag <= i_tag;
                            r_i_index <= i_index;
                            r_i_blockoffset <= i_blockoffset;
                            r_location <= location;
                        end
                    end
                    write: begin
                        if (wb_full && mem_free) begin
                            wb_o_valid <= 1;
                            mem_rw_flag <= WRITE;
                            mem_addr <= wb_o_addr;
                            mem_o_data <= wb_o_data;
                            mem_o_mask <= wb_o_mask;
                            next_state <= STATE_WRITE;
                        end
                    end
                    default: begin
                        if (!wb_empty && mem_free) begin
                            wb_o_valid <= 1;
                            mem_rw_flag <= WRITE;
                            mem_addr <= wb_o_addr;
                            mem_o_data <= wb_o_data;
                            mem_o_mask <= wb_o_mask;
                            next_state <= STATE_WRITE;
                        end else if (!pre_empty) begin
                            $display ("prefetch ready.");
                            pre_o_valid <= 1;
                            if (!valid_array[pre_o_index][pre_location] || tag_array[pre_o_index][pre_location] != pre_o_tag) begin
                                r_i_tag <= pre_o_tag;
                                r_i_index <= pre_o_index;
                                r_i_blockoffset <= {BLOCK_OFFSET_WIDTH{1'bx}};
                                r_location <= pre_location;
                                next_state <= STATE_READ_N;
                            end
                        end
                    end
                endcase
                if (prefetch && !pre_full) begin
                    $display ("fatal error2!");
                    pre_i_valid <= 1;
                    pre_i_addr <= pre_addr;
                    pre_i_data <= {`Data_Width{1'b0}};
                end
            end
            STATE_READ_C: begin
                way0_modify_index <= r_i_index;
                way1_modify_index <= r_i_index;
                way0_i_data <= mem_i_data;
                way1_i_data <= mem_i_data;
                way0_modify_blockoffset <= r_i_blockoffset;
                way1_modify_blockoffset <= r_i_blockoffset;
                way0_modify <= 0;
                way1_modify <= 0;
                way0_mask <= 4'b1111;
                way1_mask <= 4'b1111;
                if (mem_read_valid) begin
                    read_done <= 1;
                    read_data <= mem_i_data;
                    next_state <= STATE_READ_N;
                    case (r_location)
                        0: way0_modify <= 1;
                        1: way1_modify <= 1;
                    endcase
                end
            end
            STATE_READ_N: begin
                way0_modify_index <= r_i_index;
                way1_modify_index <= r_i_index;
                way0_i_data <= mem_i_data;
                way1_i_data <= mem_i_data;
                way0_modify_blockoffset <= gen_blockoffset;
                way1_modify_blockoffset <= gen_blockoffset;
                way0_modify <= 0;
                way1_modify <= 0;
                if (mem_read_valid) begin
                    if (gen_blockoffset + 4 == BLOCK_SIZE || gen_blockoffset + 8 == BLOCK_SIZE && r_i_blockoffset + 4 == BLOCK_SIZE) begin
                        next_state <= STATE_READY;
                        ctrl_array[r_i_index][r_location] <= 1;
                        ctrl_array[r_i_index][r_location^1] <= ctrl_array[r_i_index][r_location^1] ^ ctrl_array[r_i_index][r_location^1];
                        valid_array[r_i_index][r_location] <= 1;
                        tag_array[r_i_index][r_location] <= r_i_tag;
                    end
                    case (location)
                        0: way0_modify <= 1;
                        1: way1_modify <= 1;
                    endcase
                end
            end
            STATE_WRITE: begin
                if (mem_free) begin
                    next_state <= STATE_READY;
                    write_done <= 1;
                end
            end
        endcase
    end

    integer i, j;
    always @ (posedge clk) begin
        if (rst) begin
            state <= STATE_READY;
            mem_rw_flag <= 0;
            read_done <= 0;
            write_done <= 0;
            for (i = 0; i < (1 << INDEX_WIDTH); i = i + 1)
                for (j = 0; j < ASSOCIATIVITY; j = j + 1) begin
                    valid_array[i][j] <= 0;
                    ctrl_array[i][j] <= 0;
                end
        end else begin
            state <= next_state;
            case ({state, next_state})
                {STATE_READY, STATE_READ_C}: begin
                    mem_rw_flag <= READ;
                    mem_addr <= {r_i_tag, r_i_index, r_i_blockoffset};
                end
                {STATE_READY, STATE_READ_N}: begin
                    mem_rw_flag <= READ;
                    gen_blockoffset <= 0;
                    mem_addr <= {r_i_tag, r_i_index, {BLOCK_OFFSET_WIDTH{1'b0}}};
                end
                {STATE_READ_C, STATE_READ_N}: begin
                    mem_rw_flag <= READ;
                    if (r_i_blockoffset == 0) begin
                        gen_blockoffset <= 4;
                        mem_addr <= {r_i_tag, r_i_index, {BLOCK_OFFSET_WIDTH - 3{1'b0}}, {3'b100}};
                    end else begin
                        gen_blockoffset <= 0;
                        mem_addr <= {r_i_tag, r_i_index, {BLOCK_OFFSET_WIDTH{1'b0}}};
                    end
                end
                {STATE_READ_N, STATE_READ_N}: begin
                    mem_rw_flag <= READ;
                    if (mem_read_valid) begin
                        if (r_i_blockoffset == gen_blockoffset + 4) begin
                            gen_blockoffset <= gen_blockoffset + 8;
                            mem_addr <= {r_i_tag, r_i_index, gen_blockoffset + `Block_Offset_Width'd8};
                        end else begin
                            gen_blockoffset <= gen_blockoffset + 4;
                            mem_addr <= {r_i_tag, r_i_index, gen_blockoffset + `Block_Offset_Width'd4};
                        end
                    end
                end
                {STATE_READ_N, STATE_READY}: mem_rw_flag <= 0;
                {STATE_WRITE, STATE_READY}: mem_rw_flag <= 0;
            endcase
        end
    end
endmodule
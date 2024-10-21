// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "VX_platform.vh"

`TRACING_OFF
module VX_sp_ram #(
    parameter DATAW       = 1,
    parameter SIZE        = 1,
    parameter WRENW       = 1,
    parameter OUT_REG     = 0,
    parameter LUTRAM      = 0,
    parameter `STRING RDW_MODE = "R", // R: read-first, W: write-first, N: no-change
    parameter RDW_ASSERT  = 0,
    parameter RESET_RAM   = 0,
    parameter INIT_ENABLE = 0,
    parameter INIT_FILE   = "",
    parameter [DATAW-1:0] INIT_VALUE = 0,
    parameter ADDRW       = `LOG2UP(SIZE)
) (
    input wire               clk,
    input wire               reset,
    input wire               read,
    input wire               write,
    input wire [WRENW-1:0]   wren,
    input wire [ADDRW-1:0]   addr,
    input wire [DATAW-1:0]   wdata,
    output wire [DATAW-1:0]  rdata
);
    localparam WSELW = DATAW / WRENW;
    `UNUSED_PARAM (LUTRAM)

    `STATIC_ASSERT(!(WRENW * WSELW != DATAW), ("invalid parameter"))
    `STATIC_ASSERT((RDW_MODE == "R" || RDW_MODE == "W" || RDW_MODE == "N"), ("invalid parameter"))
    `UNUSED_PARAM (RDW_ASSERT)

`define RAM_INITIALIZATION \
    if (INIT_ENABLE != 0) begin : g_init \
        if (INIT_FILE != "") begin : g_file \
            initial $readmemh(INIT_FILE, ram); \
        end else begin : g_value \
            initial begin \
                for (integer i = 0; i < SIZE; ++i) begin : g_i \
                    ram[i] = INIT_VALUE; \
                end \
            end \
        end \
    end

`ifdef SYNTHESIS
    localparam FORCE_BRAM = !LUTRAM && (SIZE * DATAW >= `MAX_LUTRAM);
`ifdef QUARTUS
    `define RAM_ARRAY   reg [WRENW-1:0][WSELW-1:0] ram [0:SIZE-1];
    `define RAM_WRITE   for (integer i = 0; i < WRENW; ++i) begin \
                            if (wren[i]) begin \
                                ram[addr][i] <= wdata[i * WSELW +: WSELW]; \
                            end \
                        end
`else
    `define RAM_ARRAY   reg [DATAW-1:0] ram [0:SIZE-1];
    `define RAM_WRITE   for (integer i = 0; i < WRENW; ++i) begin \
                            if (wren[i]) begin \
                                ram[addr][i * WSELW +: WSELW] <= wdata[i * WSELW +: WSELW]; \
                            end \
                        end
`endif
    if (OUT_REG) begin : g_sync
        wire cs = read || write;
        if (FORCE_BRAM) begin : g_bram
            if (RDW_MODE == "R") begin : g_read_first
                `USE_BLOCK_BRAM `RAM_ARRAY
                `RAM_INITIALIZATION
                reg [DATAW-1:0] rdata_r;
                always @(posedge clk) begin
                    if (cs) begin
                        if (write) begin
                            `RAM_WRITE
                        end
                        rdata_r <= ram[addr];
                    end
                end
                assign rdata = rdata_r;
            end else if (RDW_MODE == "W") begin : g_write_first
                `USE_BLOCK_BRAM `RAM_ARRAY
                `RAM_INITIALIZATION
                if (WRENW > 1) begin : g_wren
                    reg [ADDRW-1:0] addr_reg;
                    always @(posedge clk) begin
                        if (cs) begin
                            if (write) begin
                                `RAM_WRITE
                            end
                            addr_reg <= addr;
                        end
                    end
                    assign rdata = ram[addr_reg];
                end else begin : g_no_wren
                    `UNUSED_VAR (wren)
                    reg [DATAW-1:0] rdata_r;
                    always @(posedge clk) begin
                        if (cs) begin
                            if (write) begin
                                ram[addr] <= wdata;
                                rdata_r <= wdata;
                            end else begin
                                rdata_r <= ram[addr];
                            end
                        end
                    end
                    assign rdata = rdata_r;
                end
            end else if (RDW_MODE == "N") begin : g_no_change
                `USE_BLOCK_BRAM `RAM_ARRAY
                `RAM_INITIALIZATION
                reg [DATAW-1:0] rdata_r;
                always @(posedge clk) begin
                    if (cs) begin
                        if (write) begin
                            `RAM_WRITE
                        end else begin
                            rdata_r <= ram[addr];
                        end
                    end
                end
                assign rdata = rdata_r;
            end
        end else begin : g_auto
            if (RDW_MODE == "R") begin : g_read_first
                `RAM_ARRAY
                `RAM_INITIALIZATION
                reg [DATAW-1:0] rdata_r;
                always @(posedge clk) begin
                    if (cs) begin
                        if (write) begin
                            `RAM_WRITE
                        end
                        rdata_r <= ram[addr];
                    end
                end
                assign rdata = rdata_r;
            end else if (RDW_MODE == "W") begin : g_write_first
                `RAM_ARRAY
                `RAM_INITIALIZATION
                if (WRENW > 1) begin : g_wren
                    reg [ADDRW-1:0] addr_reg;
                    always @(posedge clk) begin
                        if (cs) begin
                            if (write) begin
                                `RAM_WRITE
                            end
                            addr_reg <= addr;
                        end
                    end
                    assign rdata = ram[addr_reg];
                end else begin : g_no_wren
                    `UNUSED_VAR (wren)
                    reg [DATAW-1:0] rdata_r;
                    always @(posedge clk) begin
                        if (cs) begin
                            if (write) begin
                                ram[addr] <= wdata;
                                rdata_r <= wdata;
                            end else begin
                                rdata_r <= ram[addr];
                            end
                        end
                    end
                    assign rdata = rdata_r;
                end
            end else if (RDW_MODE == "N") begin : g_no_change
                `RAM_ARRAY
                `RAM_INITIALIZATION
                reg [DATAW-1:0] rdata_r;
                always @(posedge clk) begin
                    if (cs) begin
                        if (write) begin
                            `RAM_WRITE
                        end else begin
                            rdata_r <= ram[addr];
                        end
                    end
                end
                assign rdata = rdata_r;
            end
        end
    end else begin : g_async
        `UNUSED_VAR (read)
        if (FORCE_BRAM) begin : g_bram
            if (RDW_MODE == "W") begin : g_new_data
                `USE_BLOCK_BRAM `RAM_ARRAY
                `RAM_INITIALIZATION
                always @(posedge clk) begin
                    if (write) begin
                        `RAM_WRITE
                    end
                end
                assign rdata = ram[addr];
            end else begin : g_old_data
                `NO_RW_RAM_CHECK `USE_BLOCK_BRAM `RAM_ARRAY
                `RAM_INITIALIZATION
                always @(posedge clk) begin
                    if (write) begin
                        `RAM_WRITE
                    end
                end
                assign rdata = ram[addr];
            end
        end else begin : g_auto
            if (RDW_MODE == "W") begin : g_new_data
                `RAM_ARRAY
                `RAM_INITIALIZATION
                always @(posedge clk) begin
                    if (write) begin
                        `RAM_WRITE
                    end
                end
                assign rdata = ram[addr];
            end else begin : g_old_data
                `NO_RW_RAM_CHECK `RAM_ARRAY
                `RAM_INITIALIZATION
                always @(posedge clk) begin
                    if (write) begin
                        `RAM_WRITE
                    end
                end
                assign rdata = ram[addr];
            end
        end
    end
`else
    // simulation
    reg [DATAW-1:0] ram [0:SIZE-1];
    `RAM_INITIALIZATION

    always @(posedge clk) begin
        if (RESET_RAM && reset) begin
            for (integer i = 0; i < SIZE; ++i) begin
                ram[i] <= DATAW'(INIT_VALUE);
            end
        end else if (write) begin
            for (integer i = 0; i < WRENW; ++i) begin
                if (wren[i]) begin
                    ram[addr][i * WSELW +: WSELW] <= wdata[i * WSELW +: WSELW];
                end
            end
        end
    end

    if (OUT_REG) begin : g_sync
        if (RDW_MODE == "R") begin : g_read_first
            reg [DATAW-1:0] rdata_r;
            always @(posedge clk) begin
                if (read || write) begin
                    rdata_r <= ram[addr];
                end
            end
            assign rdata = rdata_r;
        end else if (RDW_MODE == "W") begin : g_write_first
            reg [ADDRW-1:0] addr_reg;
            always @(posedge clk) begin
                if (read || write) begin
                    addr_reg <= addr;
                end
            end
            assign rdata = ram[addr_reg];
        end else if (RDW_MODE == "N") begin : g_no_change
            reg [DATAW-1:0] rdata_r;
            always @(posedge clk) begin
                if (read && ~write) begin
                    rdata_r <= ram[addr];
                end
            end
            assign rdata = rdata_r;
        end
    end else begin : g_async
        `UNUSED_VAR (read)
        if (RDW_MODE == "W") begin : g_rwcheck
            assign rdata = ram[addr];
        end else begin : g_no_rwcheck
            reg [DATAW-1:0] prev_data;
            reg [ADDRW-1:0] prev_waddr;
            reg prev_write;
            always @(posedge clk) begin
                if (reset) begin
                    prev_write <= 0;
                    prev_data  <= '0;
                    prev_waddr <= '0;
                end else begin
                    prev_write <= write;
                    prev_data  <= ram[addr];
                    prev_waddr <= addr;
                end
            end
            assign rdata = (prev_write && (prev_waddr == addr)) ? prev_data : ram[addr];
            if (RDW_ASSERT) begin : g_rw_asert
                `RUNTIME_ASSERT(~read || (rdata == ram[addr]), ("%t: read after write hazard", $time))
            end
        end
    end
`endif

endmodule
`TRACING_ON

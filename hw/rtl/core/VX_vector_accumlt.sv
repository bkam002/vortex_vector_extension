`include "VX_define.vh"
`include "VX_config.vh"

// Vector Accummulate Unit - 
// Functionality:
//  1. Check for Unrolling condition - (XLEN * NUM_THREADS) < VLEN 
//  2. Accumulate multiple Vector register element updates
//  3. Return single Vector register write back
module VX_vector_accumlt #(
    parameter VLEN = `VLEN_ARCH
) (
    input wire              clk,
    input wire              reset,
    
    // Inputs
    VX_commit_if.slave     alu_commit_slave_if,

    //Vector CSR configuration values
    VX_vector_csr_if.slave vector_csr_if,
    
    // Outputs
    VX_commit_if.master     alu_commit_master_if    
);

    `UNUSED_VAR(clk)
    `UNUSED_VAR(reset)

    //Local paramters 
    localparam VLMAX_SEW32 = VLEN / 32 ;
    localparam VLMAX_SEW64 = VLEN / 64 ;  
    localparam UNROLL_EN = (`XLEN == 32) ? (VLMAX_SEW32 > 4 ) : (VLMAX_SEW64 > 4);
    localparam CNTR_WIDTH = `LOG2UP(`NUM_THREADS);
    localparam NW_WIDTH = `UP(`NW_BITS);
    localparam DATAW_WB  =  NW_WIDTH + 32 + `NUM_THREADS + `NR_BITS + (`NUM_THREADS * `XLEN) + 1 + 1 + (`NUM_THREADS *`VLEN_ARCH);
    //Internal Signals 

    //wire [2:0] vsew;
    //wire [2:0] lmul;
    //wire [4:0] vl;

    reg [CNTR_WIDTH -1:0] data_accmlt_cntr;

    

    reg [`NUM_THREADS-1:0][`VLEN_ARCH-1:0]    data_out_r;

    wire vector_accum_ready_out;
    reg  vd_data_full;
    wire vd_cmt_ready;

    genvar i;
    int j;

    VX_commit_if     alu_commit_master_v_if;


    if(UNROLL_EN == 0) 
    begin
        reg [`NUM_THREADS-1:0][`VLEN_ARCH-1:0]    data_out;
        //Counter block to manage the data binding

        always@(posedge clk)
        begin
            if(reset)
            begin
                data_accmlt_cntr <= CNTR_WIDTH'(0);
            end
            else if (alu_commit_slave_if.valid && vector_accum_ready_out)
            begin
                data_accmlt_cntr <= data_accmlt_cntr + 1'b1;
            end
        end

        //Data binding block   
        for (i = 0; i<`NUM_THREADS; i++)
        begin
            always@(*)
            begin
                data_out[i] = data_out_r[i];
                if(alu_commit_slave_if.valid) // make it pulse if valid stays for 2 cycle without ready
                begin
                    data_out[data_accmlt_cntr][(((i+1)* `XLEN)-1):(i * `XLEN)] = alu_commit_slave_if.data[i];
                end
            end
        end

        //Register the binding data
        always@(posedge clk)
        begin
            if(reset)
            begin
                for (j = 0; j<`NUM_THREADS; j++)
                begin
                    data_out_r[j] <= {`VLEN_ARCH{1'b0}};
                end
            end
            else
            begin
                for (j = 0; j<`NUM_THREADS; j++)
                begin
                    data_out_r[j] <= data_out[j];
                end
            end
        end

        //Full condition register
        always@(posedge clk)
        begin
            if(reset)
            begin
                vd_data_full <= 1'b0;
            end
            else if(vd_cmt_ready)
            begin
                vd_data_full <= 1'b0;
            end
            else if(data_accmlt_cntr == 2'd3)
            begin
                vd_data_full <= 1'b1;
            end
        end

        
        //assign alu_commit_master_v_if.ready = alu_commit_slave_if.is_vec ? alu_commit_master_if.ready : 1'b0;
        
    end
    else
    begin
        //Counter to manage the unrolling within thread - Simple case of 2 cycle per VREG - works for both SEW - 32 and 64
        reg      unroll_cntr;
        reg [`VLEN_ARCH-1:0] vd_data_unroll;
        reg [`VLEN_ARCH-1:0] vd_data_unroll_r;
        reg [`NUM_THREADS * `XLEN -1:0] data_select; 
        always@(posedge clk)
        begin
            if(reset)
            begin
                unroll_cntr <= 1'b0;
            end
            else if (alu_commit_slave_if.valid && vector_accum_ready_out)
            begin
                unroll_cntr <= unroll_cntr + 1'b1;
            end
        end

        //Counter block to manage the data binding

        always@(posedge clk)
        begin
            if(reset)
            begin
                data_accmlt_cntr <= CNTR_WIDTH'(0);
            end
            else if (alu_commit_slave_if.valid && (unroll_cntr == 1'b1))
            begin
                data_accmlt_cntr <= data_accmlt_cntr + 1'b1;
            end
        end

        //Data selection block for Unrolling case -- 4 < VL < VLMAX
        for (i = 0; i<`NUM_THREADS; i++)
        begin
            always@(*)
            begin
                data_select = 'd0;
                if(alu_commit_slave_if.valid) // make it pulse if valid stays for 2 cycle without ready
                begin
                    data_select[(((i+1)* `XLEN)-1):(i * `XLEN)] = alu_commit_slave_if.data[i];
                end
            end
        end
        always@(*)
        begin
            vd_data_unroll = vd_data_unroll_r;
            if(unroll_cntr == 1'b0)
            begin
                vd_data_unroll[(VLEN/2) -1:0] = data_select;
            end
            else
            begin
                vd_data_unroll[VLEN-1:(VLEN/2)] = data_select;
            end
        end

        //Register block for per thread data
        always@(posedge clk)
        begin
            if(reset)
            begin
                vd_data_unroll_r <= VLEN'(0);
            end
            else
            begin
                vd_data_unroll_r <= vd_data_unroll;
            end
        end

        //Packing all thread data -
        //Register the binding data
        always@(posedge clk)
        begin
            if(reset)
            begin
                for (j = 0; j<`NUM_THREADS; j++)
                begin
                    data_out_r[j] <= {`VLEN_ARCH{1'b0}};
                end
            end
            else
            begin
                begin
                    data_out_r[data_accmlt_cntr] <= vd_data_unroll;
                end
            end
        end

        //Full condition register
        always@(posedge clk)
        begin
            if(reset)
            begin
                vd_data_full <= 1'b0;
            end
            else if(vd_cmt_ready)
            begin
                vd_data_full <= 1'b0;
            end
            else if(data_accmlt_cntr == 2'd3)
            begin
                vd_data_full <= 1'b1;
            end
        end

    end

    assign vector_accum_ready_out = !vd_data_full;

    VX_skid_buffer #(
        .DATAW   (DATAW_WB),
        .OUT_REG (1)
    ) vec_acc_buffer (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (vd_data_full),
        .ready_in  (vd_cmt_ready),
        .data_in   ({alu_commit_slave_if.wid, alu_commit_slave_if.PC, alu_commit_slave_if.tmask, alu_commit_slave_if.rd, alu_commit_slave_if.data, alu_commit_slave_if.eop, alu_commit_slave_if.is_vec, data_out_r}),
        .data_out  ({alu_commit_master_v_if.wid, alu_commit_master_v_if.PC, alu_commit_master_v_if.tmask, alu_commit_master_v_if.rd, alu_commit_master_v_if.data, alu_commit_master_v_if.eop, alu_commit_master_v_if.is_vec, alu_commit_master_v_if.vd_data}),
        .valid_out (alu_commit_master_v_if.valid),
        .ready_out (alu_commit_master_if.ready)
    );

    //Mux to select the data based on EX type
    assign alu_commit_master_if.valid = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.valid : alu_commit_slave_if.valid;
    assign alu_commit_master_if.uuid = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.uuid :alu_commit_slave_if.uuid;
    assign alu_commit_master_if.wid = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.wid :alu_commit_slave_if.wid;
    assign alu_commit_master_if.tmask = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.tmask :alu_commit_slave_if.tmask;
    assign alu_commit_master_if.PC = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.PC :alu_commit_slave_if.PC;
    assign alu_commit_master_if.data = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.data :alu_commit_slave_if.data;
    assign alu_commit_master_if.rd = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.rd :alu_commit_slave_if.rd;
    assign alu_commit_master_if.wb = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.wb :alu_commit_slave_if.wb;
    assign alu_commit_master_if.eop = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.eop :alu_commit_slave_if.eop;
    assign alu_commit_master_if.is_vec = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.is_vec: alu_commit_slave_if.is_vec;
    assign alu_commit_master_if.vd_data = alu_commit_slave_if.is_vec ? alu_commit_master_v_if.vd_data: alu_commit_slave_if.vd_data;
    assign alu_commit_slave_if.ready = alu_commit_slave_if.is_vec ? vector_accum_ready_out :alu_commit_master_if.ready;


endmodule

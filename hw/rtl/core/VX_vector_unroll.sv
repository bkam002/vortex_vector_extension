`include "VX_define.vh"
`include "VX_config.vh"

// Vector Unroll Unit
// Functionality:
//  1. Check for Unrolling condition - (XLEN * NUM_THREADS) < VLEN -- VL < 4 (NUM_THREADS)
//  2. Unroll the vector operations to multiple cycle 
//  3. Handle the ready signal from ALU unit.
module VX_vector_unroll #(
    parameter VLEN = `VLEN_ARCH
) (
    input wire                                   clk,
    input wire                                   reset,
    
    // Inputs
    input wire                                   valid_in,
    input wire                                   ready_out,
    input wire [`NUM_THREADS-1:0][`VLEN_ARCH-1:0] vs1_data_in,
    input wire [`NUM_THREADS-1:0][`VLEN_ARCH-1:0] vs2_data_in,

    //Vector CSR configuration values
    //VX_vector_csr_if.slave vector_csr_if,
    

    // Outputs
    output wire [`NUM_THREADS-1:0][`XLEN-1:0]    vs1_data_out,
    output wire [`NUM_THREADS-1:0][`XLEN-1:0]    vs2_data_out
);
   

    //Local paramters 
    localparam VLMAX_SEW32 = VLEN / 32 ;
    localparam VLMAX_SEW64 = VLEN / 64 ;  
    localparam UNROLL_EN = (`XLEN == 32) ? (VLMAX_SEW32 > 4 ) : (VLMAX_SEW64 > 4);
    localparam CNTR_WIDTH = `LOG2UP(`NUM_THREADS);
    //Functionality one - Unpacking Vector register to multiple threads rs1 and rs2.
    //Input and CSR signals needed - vsew, vl, lmul(1)
    

    //Internal Signals 

    //wire [2:0] vsew;
    //wire [2:0] lmul;
    //wire [4:0] vl;

    reg [CNTR_WIDTH -1:0] unpack_cntr;

    genvar i;
    int j;

    reg [`NUM_THREADS-1:0][`XLEN-1:0]    data_out_1;
    reg [`NUM_THREADS-1:0][`XLEN-1:0]    data_out_2;

    reg [`NUM_THREADS-1:0][`XLEN-1:0]    data_out_1_r;
    reg [`NUM_THREADS-1:0][`XLEN-1:0]    data_out_2_r;


    //Unrolling Logic-
    if(UNROLL_EN == 0)
    begin
        //Counter block to manage the unrolling

        always@(posedge clk)
        begin
            if(reset)
            begin
                unpack_cntr <= CNTR_WIDTH'(0);
            end
            else if (valid_in && ready_out)
            begin
                unpack_cntr <= unpack_cntr + 1'b1;
            end
        end

        //unpacking block   
        for (i = 0; i<`NUM_THREADS; i++)
        begin
            always@(*)
            begin
                data_out_1[i] = data_out_1_r[i];
                data_out_2[i] = data_out_2_r[i];
                if(valid_in) // make it pulse if valid stays for 2 cycle without ready
                begin
                    data_out_1[i] = vs1_data_in[unpack_cntr][(((i+1)* `XLEN)-1):(i * `XLEN)];
                    data_out_2[i] = vs2_data_in[unpack_cntr][(((i+1)* `XLEN)-1):(i * `XLEN)];
                end
            end
        end
        
        

        //Register the unpacked data
        always@(posedge clk)
        begin
            if(reset)
            begin
                for (j = 0; j<`NUM_THREADS; j++)
                begin
                    data_out_1_r[j] <= {`XLEN{1'b0}};
                    data_out_2_r[j] <= {`XLEN{1'b0}};
                end
            end
            else
            begin
                for (j = 0; j<`NUM_THREADS; j++)
                begin
                    data_out_1_r[j] <= data_out_1[j];
                    data_out_2_r[j] <= data_out_2[j];
                end
            end
        end

        for (i = 0; i<`NUM_THREADS; i++)
        begin
            assign vs1_data_out[i] = data_out_1_r[i];
            assign vs2_data_out[i] = data_out_2_r[i];
        end
    end        
    else
    begin
        //Counter to manage the unrolling within thread - Simple case of 2 cycle per VREG - works for both SEW - 32 and 64
        reg      unroll_cntr;
        reg [`VLEN_ARCH-1:0] vs1_data_unroll;
        reg [`VLEN_ARCH-1:0] vs2_data_unroll;

        always@(posedge clk)
        begin
            if(reset)
            begin
                unroll_cntr <= 1'b0;
            end
            else if (valid_in && ready_out)
            begin
                unroll_cntr <= unroll_cntr + 1'b1;
            end
        end
        //Counter block to manage the unrolling

        always@(posedge clk)
        begin
            if(reset)
            begin
                unpack_cntr <= CNTR_WIDTH'(0);
            end
            else if ((valid_in && ready_out) && (unroll_cntr == 1'b1))
            begin
                unpack_cntr <= unpack_cntr + 1'b1;
            end
        end

        //Data selection block for Unrolling case -- 4 < VL < VLMAX
        always@(*)
        begin
            if(unroll_cntr == 1'b0)
            begin
                vs1_data_unroll = vs1_data_in[unpack_cntr][(VLEN/2) -1:0];
                vs2_data_unroll = vs2_data_in[unpack_cntr][(VLEN/2) -1:0];
            end
            else
            begin
                vs1_data_unroll = vs1_data_in[unpack_cntr][VLEN-1:(VLEN/2)];
                vs2_data_unroll = vs2_data_in[unpack_cntr][VLEN-1:(VLEN/2)];
            end
        end

        //unpacking block
        for (i = 0; i<`NUM_THREADS; i++)
        begin
            always@(*)
            begin
                data_out_1[i] = data_out_1_r[i];
                data_out_2[i] = data_out_2_r[i];
                if(valid_in) // make it pulse if valid stays for 2 cycle without ready
                begin
                    data_out_1[i] = vs1_data_unroll[(((i+1)* `XLEN)-1):(i * `XLEN)];
                    data_out_2[i] = vs2_data_unroll[(((i+1)* `XLEN)-1):(i * `XLEN)];
                end
            end
        end

        //Register the unpacked data
        always@(posedge clk)
        begin
            if(reset)
            begin
                for (j = 0; j<`NUM_THREADS; j++)
                begin
                    data_out_1_r[j] <= {`XLEN{1'b0}};
                    data_out_2_r[j] <= {`XLEN{1'b0}};
                end
            end
            else
            begin
                for (j = 0; j<`NUM_THREADS; j++)
                begin
                    data_out_1_r[j] <= data_out_1[j];
                    data_out_2_r[j] <= data_out_2[j];
                end
            end
        end

        for (i = 0; i<`NUM_THREADS; i++)
        begin
            assign vs1_data_out[i] = data_out_1_r[i];
            assign vs2_data_out[i] = data_out_2_r[i];
        end
    end


    //Logical block habdling multiple request to ALU unit.

endmodule

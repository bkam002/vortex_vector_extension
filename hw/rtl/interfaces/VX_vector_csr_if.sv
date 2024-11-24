`include "VX_define.vh"

interface VX_vector_csr_if ();

    wire [`XLEN-1:0] vtype;
    wire [`XLEN-1:0] vl;
    wire [`XLEN-1:0] vlenb;

    modport master (
        output vtype,
        output vl,
        output vlenb
    );

    modport slave (
        input vtype,
        input vl,
        input vlenb
    );

endinterface

`timescale 1ns/1ps

// Registered 32-bit modular adder for the fast DSP schedule service.
// The DSP output register is enabled only when the surrounding elastic
// pipeline advances.  The functional fallback models the same behavior for
// simulators without the Vivado UNISIM library.
module dsp58_add32_registered (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        ce_i,
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    output wire [31:0] sum_o
);
`ifdef SYNTHESIS
    wire [57:0] p;
    DSP58 #(
        .AREG(0), .BREG(0), .CREG(0), .DREG(0), .ADREG(0), .MREG(0),
        .PREG(1), .ACASCREG(0), .BCASCREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0), .INMODEREG(0), .OPMODEREG(0),
        .USE_MULT("NONE"), .USE_SIMD("ONE58")
    ) u_dsp58 (
        .A({26'b0, b_i[31:24]}), .ACIN(34'b0), .B(b_i[23:0]),
        .BCIN(24'b0), .C({26'b0, a_i}), .D(27'b0), .PCIN(58'b0),
        .ALUMODE(4'b0000), .OPMODE(9'b000110011), .INMODE(5'b0),
        .CARRYIN(1'b0), .CARRYINSEL(3'b000), .CARRYCASCIN(1'b0),
        .CLK(clk_i), .ASYNC_RST(1'b0), .MULTSIGNIN(1'b0), .NEGATE(3'b0),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0), .CEALUMODE(1'b0),
        .CEB1(1'b0), .CEB2(1'b0), .CEC(1'b0), .CECARRYIN(1'b0),
        .CECTRL(1'b0), .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0),
        .CEP(ce_i), .RSTA(1'b0), .RSTALLCARRYIN(1'b0), .RSTALUMODE(1'b0),
        .RSTB(1'b0), .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(~rst_ni),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(), .MULTSIGNOUT(),
        .OVERFLOW(), .P(p), .PATTERNBDETECT(), .PATTERNDETECT(), .PCOUT(),
        .UNDERFLOW(), .XOROUT()
    );
    assign sum_o = p[31:0];
`else
    reg [31:0] sum_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            sum_q <= 32'b0;
        else if (ce_i)
            sum_q <= a_i + b_i;
    end
    assign sum_o = sum_q;
`endif
endmodule

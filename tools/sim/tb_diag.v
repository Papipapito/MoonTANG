// tb_diag.v — volcado crudo y ALINEADO de la linea I2S, para leer directamente
// la correspondencia canal <-> LRCLK y la alineacion de bits.
`timescale 1ns/1ps
module tb_diag;
    reg clk = 0, rst_n = 0;
    always #100 clk = ~clk;

    reg signed [15:0] sampL = 16'hAAAA;   // 1010101010101010
    reg signed [15:0] sampR = 16'h5555;   // 0101010101010101

    wire lr, din, bclk, req;
    reg signed [15:0] s;
    always @(posedge clk) s <= lr ? sampL : sampR;   // el mux del top

    I2S_AUDIO_TX #(.SAMPLE_WIDTH(16)) dut (
        .CLK_DAC(clk), .RESET_n(rst_n), .SAMPLE_IN(s),
        .REQ(req), .DAC_BCLK(bclk), .DAC_LRCLK(lr), .DAC_DIN(din));

    integer i;
    reg [0:79] vlr, vdin, vreq;

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (80) @(posedge clk);           // dejar estabilizar

        // capturar las tres señales EN EL MISMO flanco
        for (i = 0; i < 80; i = i + 1) begin
            @(posedge bclk);
            vlr[i]  = lr;
            vdin[i] = din;
            vreq[i] = req;
        end

        $write("LRCLK: "); for (i = 0; i < 80; i = i + 1) $write("%b", vlr[i]);
        $write("\nDIN  : "); for (i = 0; i < 80; i = i + 1) $write("%b", vdin[i]);
        $write("\nREQ  : "); for (i = 0; i < 80; i = i + 1) $write("%b", vreq[i]);
        $display("\n");
        $display("L = 0x%04x = 1010101010101010", sampL);
        $display("R = 0x%04x = 0101010101010101", sampR);
        $display("(estandar I2S: LRCLK=0 -> canal IZQUIERDO)");
        $finish;
    end
endmodule

// ============================================================================
// tb_i2s.v — verifica el camino de audio I2S de MoonTANG.
//
// LO QUE VERIFICA: la fase del mux estereo del top,
//     i2s_sample <= dac_lrclk_w ? sampL : sampR;
// deducida leyendo el RTL de I2S_AUDIO_TX. Si estuviera invertida, el cartucho
// sacaria los canales cambiados — un fallo caro de ver en placa.
//
// METODO (el que funciono en tb_diag): capturar LRCLK y DIN en el MISMO flanco
// de BCLK, localizar los flancos de LRCLK y deserializar los 16 bits que
// empiezan UN BCLK DESPUES del flanco (retardo de 1 bit del estandar I2S,
// confirmado empiricamente). LRCLK=0 -> canal izquierdo.
// ============================================================================
`timescale 1ns/1ps

module tb_i2s;

    reg clk_dac = 0, rst_n = 0;
    always #100 clk_dac = ~clk_dac;

    reg signed [15:0] sampL, sampR;

    // --- el bloque EXACTO del top de MoonTANG ---
    wire dac_lrclk_w, dac_din, dac_bclk;
    reg signed [15:0] i2s_sample;
    always @(posedge clk_dac) i2s_sample <= dac_lrclk_w ? sampL : sampR;

    I2S_AUDIO_TX #(.SAMPLE_WIDTH(16)) dut (
        .CLK_DAC(clk_dac), .RESET_n(rst_n), .SAMPLE_IN(i2s_sample),
        .REQ(), .DAC_BCLK(dac_bclk), .DAC_LRCLK(dac_lrclk_w), .DAC_DIN(dac_din));

    integer errors = 0;
    integer checks = 0;

    reg [0:99] vlr, vdin;
    reg [15:0] gL, gR, acc;
    integer    k, base;

    task capture_frame;
        begin
            gL = 16'hxxxx; gR = 16'hxxxx;
            for (k = 0; k < 100; k = k + 1) begin
                @(posedge dac_bclk);
                vlr[k]  = dac_lrclk_w;
                vdin[k] = dac_din;
            end
            for (base = 1; base < 82; base = base + 1) begin
                if (vlr[base] !== vlr[base-1]) begin
                    acc = 16'd0;
                    for (k = 0; k < 16; k = k + 1) acc = {acc[14:0], vdin[base+1+k]};
                    if (vlr[base] === 1'b0) gL = acc;
                    else                    gR = acc;
                end
            end
        end
    endtask

    task check;
        input [15:0] eL;
        input [15:0] eR;
        begin
            capture_frame;
            checks = checks + 1;
            if (gL !== eL || gR !== eR) begin
                $display("  [FAIL] L=0x%04x (esperado 0x%04x)   R=0x%04x (esperado 0x%04x)",
                         gL, eL, gR, eR);
                errors = errors + 1;
            end
            else $display("  [ok]   L=0x%04x   R=0x%04x", gL, gR);
        end
    endtask

    initial begin
        sampL = 16'h0000; sampR = 16'h0000;
        repeat (10) @(posedge clk_dac);
        rst_n = 1;
        repeat (80) @(posedge clk_dac);

        $display("== I2S: canales estereo y alineacion de bits ==");

        sampL = 16'h1234; sampR = 16'h7ABC; repeat(80) @(posedge clk_dac); check(16'h1234, 16'h7ABC);
        sampL = 16'h7FFF; sampR = 16'h0000; repeat(80) @(posedge clk_dac); check(16'h7FFF, 16'h0000);
        sampL = 16'h0000; sampR = 16'h7FFF; repeat(80) @(posedge clk_dac); check(16'h0000, 16'h7FFF);
        sampL = 16'hFFFF; sampR = 16'h8000; repeat(80) @(posedge clk_dac); check(16'hFFFF, 16'h8000);
        sampL = 16'hAAAA; sampR = 16'h5555; repeat(80) @(posedge clk_dac); check(16'hAAAA, 16'h5555);
        sampL = 16'h5555; sampR = 16'hAAAA; repeat(80) @(posedge clk_dac); check(16'h5555, 16'hAAAA);

        $display("== %0d comprobaciones, %0d errores ==", checks, errors);
        if (errors == 0)
            $display("RESULTADO: PASS - canales en su sitio y sin desplazamiento de bit");
        else
            $display("RESULTADO: FAIL");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("RESULTADO: FAIL (timeout)");
        $finish;
    end

endmodule

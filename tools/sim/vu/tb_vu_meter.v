// ============================================================================
// tb_vu_meter.v — prueba unitaria de fpga/src/vu_meter.v.
//
// Comprueba, contra un modelo de referencia escrito con logaritmos reales:
//   1. la conversion de pico a segmentos (28 segmentos de ~1,5 dB; el de
//      arriba es fondo de escala): no puede desviarse mas de un segmento;
//   2. casos exactos: silencio = 0, fondo de escala = 28, -32768 no desborda;
//   3. la balistica: sube al instante, cae un segmento cada dos cuadros, y la
//      marca de pico aguanta HOLD cuadros antes de caer.
//
// Uso: iverilog -g2012 -s tb_vu_meter -o /tmp/vu tools/sim/vu/tb_vu_meter.v fpga/src/vu_meter.v && vvp /tmp/vu
// ============================================================================
`timescale 1ns/1ps

module tb_vu_meter;
    reg clk = 0;
    always #9.26 clk = ~clk;                // 54 MHz

    reg         frame_tog = 0;
    reg  signed [15:0] s0 = 0, s1 = 0;
    wire [9:0]  level, peak;

    vu_meter #(.NCH(2), .HOLD(5)) dut (
        .clk(clk), .frame_tog(frame_tog),
        .samples({s1, s0}), .level(level), .peak(peak)
    );
    wire [4:0] lv0 = level[4:0], lv1 = level[9:5], pk0 = peak[4:0];

    integer errors = 0, checks = 0;
    task ok(input cond, input [799:0] what);
        begin
            checks = checks + 1;
            if (cond !== 1'b1) begin errors = errors + 1; $display("  [FAIL] %0s", what); end
        end
    endtask

    // un cuadro: la muestra `v` suena un rato y luego llega el cambio de cuadro.
    // El nivel que se ve tras el SIGUIENTE cambio de cuadro es el de este pico.
    task frame(input signed [15:0] v0, input signed [15:0] v1);
        begin
            s0 = v0; s1 = v1;
            repeat (40) @(posedge clk);
            frame_tog = ~frame_tog;
            repeat (10) @(posedge clk);
        end
    endtask

    // referencia: segmentos = redondeo de 28 + 20*log10(|x|/32768)/1,505 hacia abajo
    function integer ref_segs(input integer mag);
        real db;
        integer n;
        begin
            if (mag < 1) ref_segs = 0;
            else begin
                db = 20.0 * $ln(mag / 32768.0) / $ln(10.0);
                n = $rtoi($floor(28.0 + db / 1.505 + 1.0));
                ref_segs = (n < 0) ? 0 : (n > 28) ? 28 : n;
            end
        end
    endfunction

    integer i, mag, expd, worst;
    reg [4:0] lv_prev;

    initial begin
        repeat (20) @(posedge clk);

        $display("== 1. pico -> segmentos, contra la referencia logaritmica ==");
        worst = 0;
        for (i = 0; i < 200; i = i + 1) begin
            mag = (i < 20) ? i * 13 : $rtoi(32767.0 * $exp(-(199 - i) * 0.03));
            // limpia la barra (cuadros en silencio de sobra) y mide
            repeat (70) frame(16'sd0, 16'sd0);
            frame(mag[15:0], -mag[15:0]);
            frame(16'sd0, 16'sd0);
            expd = ref_segs(mag);
            if (lv0 > expd + 1 || lv0 + 1 < expd) begin
                errors = errors + 1;
                $display("  [FAIL] |x| = %0d: %0d segmentos, referencia %0d", mag, lv0, expd);
            end
            if ((lv0 > expd ? lv0 - expd : expd - lv0) > worst) worst = (lv0 > expd ? lv0 - expd : expd - lv0);
            ok(lv0 === lv1, "positivo y negativo dan la misma barra");
            checks = checks + 1;
        end
        $display("  desviacion maxima frente a la referencia: %0d segmento(s) en 200 amplitudes", worst);

        $display("== 2. casos exactos ==");
        repeat (70) frame(16'sd0, 16'sd0);
        ok(lv0 == 5'd0 && pk0 == 5'd0, "silencio: barra y marca a cero");
        frame(16'sh7FFF, 16'sh8000); frame(16'sd0, 16'sd0);
        ok(lv0 == 5'd28, "fondo de escala positivo = 28 segmentos");
        ok(lv1 == 5'd28, "-32768 = 28 segmentos (sin desbordar)");
        repeat (70) frame(16'sd0, 16'sd0);
        frame(16'sd255, 16'sd256); frame(16'sd0, 16'sd0);
        ok(lv0 == 5'd0 && lv1 == 5'd1, "umbral del primer segmento: 256 lo enciende, 255 no");

        $display("== 3. balistica ==");
        repeat (70) frame(16'sd0, 16'sd0);
        frame(16'sd16000, 16'sd0); frame(16'sd0, 16'sd0);
        lv_prev = lv0;
        ok(lv_prev >= 5'd23, "sube al instante");
        frame(16'sd0, 16'sd0); frame(16'sd0, 16'sd0);
        ok(lv0 == lv_prev - 5'd1, "cae un segmento cada dos cuadros");
        ok(pk0 == lv_prev, "la marca de pico aguanta mientras tanto");
        frame(16'sd0, 16'sd0);                 // 4 cuadros tras el pico: HOLD = 5
        ok(pk0 == lv_prev, "y sigue ahi dentro del tiempo de retencion");
        repeat (10) frame(16'sd0, 16'sd0);
        ok(pk0 < lv_prev && pk0 > lv0, "despues cae, pero por encima de la barra");
        repeat (80) frame(16'sd0, 16'sd0);
        ok(lv0 == 5'd0 && pk0 == 5'd0, "y todo vuelve a cero");

        $display("== %0d comprobaciones, %0d errores ==", checks, errors);
        if (errors == 0) $display("RESULTADO: PASS");
        else             $display("RESULTADO: FAIL");
        $finish;
    end
endmodule

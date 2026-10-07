// ============================================================================
// tb_vu_screen.v - banco de pruebas de vu_screen.v.                (MoonTANG)
//
// Genera el barrido 858x525 igual que hdmi.sv (cx/cy registrados, vuelta en
// 857 y 524) y captura `rgb` con la cadencia que pide hdmi: el rgb que hay en
// un ciclo es el del pixel (cx, cy) del ciclo ANTERIOR.
//
//  1. Tres cuadros de muestra, volcados a PPM (vu_check.py los convierte a PNG
//     y los compara pixel a pixel con un modelo independiente):
//        a  todo a cero, YRW801 cargando, sin MSX
//        b  niveles intermedios distintos en cada barra, picos por encima, OK
//        c  todo al maximo, error de ROM
//     Sobre el "c" se comprueba ademas la geometria de los segmentos (bordes).
//  2. Barrido de niveles: 29 cuadros en los que cada barra pasa por 0..28 (sin
//     marca de pico). Se muestrea el centro de cada segmento, se cuenta cuantos
//     estan encendidos y se exige que coincida con `level`.
//  3. Marca de pico: 29 cuadros con el pico de cada barra pasando por 0..28 y
//     niveles variados (por debajo, a la par y por encima del pico).
//  4. Valores fuera de rango (29..31) y st_rom = 3: no deben romper nada. Estos
//     dos cuadros tambien se vuelcan y se comparan con el modelo.
//
// Los cuadros que se vuelcan llevan el barrido completo. En los 58 de los
// puntos 2 y 3 solo se miran las barras, asi que por defecto el banco salta de
// linea en linea por las unicas que se muestrean (primera, central y ultima de
// cada barra, mas la 0 y dos del borrado): 21 lineas por cuadro en vez de 525,
// y la simulacion baja de unos 6 minutos a medio. Cada linea sigue siendo un
// barrido horizontal completo de 858 ciclos. Con +completo se hacen tambien
// esos cuadros enteros.
//
// Ademas: ningun pixel visible con X y negro en todo el borrado.
// Acaba con "RESULTADO: PASS" o "RESULTADO: FAIL".
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

// texto del pie; run_vu.sh lo pasa con -DVU_BUILD (y el mismo a vu_check.py)
`ifndef VU_BUILD
`define VU_BUILD "2026-10-04"
`endif

module tb_vu_screen;

    localparam integer HT = 858, VT = 525, HA = 720, VA = 480;

    // colores de las barras (copia independiente de los de vu_screen.v), tal como
    // salen: en rango limitado, 16 + c * 219 / 255 de los de diseño
    //   (06080E, 0A2410 2A2608 2A0C08, 20E040 F0D020 F03020, B0FFC0 FFF8A0 FFA090)
    localparam [23:0] C_BG    = 24'h15171C;
    localparam [23:0] C_OFF_G = 24'h192F1E, C_OFF_Y = 24'h343117, C_OFF_R = 24'h341A17;
    localparam [23:0] C_ON_G  = 24'h2BD047, C_ON_Y  = 24'hDEC32B, C_ON_R  = 24'hDE392B;
    localparam [23:0] C_PK_G  = 24'hA7EBB5, C_PK_Y  = 24'hEBE599, C_PK_R  = 24'hEB998C;

    function integer bar_y;                 // y de arriba de la barra b
        input integer b;
        begin
            case (b)
                0:       bar_y = 112;       // FM L
                1:       bar_y = 144;       // FM R
                2:       bar_y = 200;       // WAVE L
                3:       bar_y = 232;       // WAVE R
                4:       bar_y = 288;       // OUT L
                default: bar_y = 320;       // OUT R
            endcase
        end
    endfunction

    function integer row_dy;                // las tres filas que se muestrean
        input integer r;
        begin
            case (r)
                0:       row_dy = 0;        // primera
                1:       row_dy = 12;       // central
                default: row_dy = 23;       // ultima
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    // Reloj y barrido (como hdmi.sv)
    // ------------------------------------------------------------------
    reg clk = 1'b0;
    always #18.5 clk = ~clk;                // 27 MHz

    reg fast = 1'b0;                        // barrido abreviado (puntos 2 y 3)

    // siguiente linea del barrido abreviado: la primera de la lista que queda
    // por debajo de y; al acabar, 481 y 500 (borrado vertical) y vuelta a 0
    function [9:0] fast_next;
        input [9:0] y;
        integer b, r, t;
        reg     done;
        begin
            fast_next = 10'd0;
            done      = 1'b0;
            for (b = 0; b < 6; b = b + 1)
                for (r = 0; r < 3; r = r + 1) begin
                    t = bar_y(b) + row_dy(r);
                    if (!done && y < t) begin
                        fast_next = t[9:0];
                        done      = 1'b1;
                    end
                end
            if (!done && y < 10'd481) begin fast_next = 10'd481; done = 1'b1; end
            if (!done && y < 10'd500) begin fast_next = 10'd500; done = 1'b1; end
        end
    endfunction

    // Sale del reset en la linea 499 (como hdmi con START_Y = 499): asi el
    // primer cuadro de muestra empieza enseguida, sin simular uno de mas.
    reg       rst_n = 1'b0;
    reg [9:0] cx = 10'd0;
    reg [9:0] cy = 10'd499;
    always @(posedge clk) begin
        if (!rst_n) begin
            cx <= 10'd0;
            cy <= 10'd499;
        end
        else begin
            cx <= (cx == HT-1) ? 10'd0 : cx + 10'd1;
            if (cx == HT-1) begin
                if (fast) cy <= fast_next(cy);
                else      cy <= (cy == VT-1) ? 10'd0 : cy + 10'd1;
            end
        end
    end

    reg  [29:0] level  = 30'd0;
    reg  [29:0] peak   = 30'd0;
    reg  [1:0]  st_rom = 2'd0;
    reg         st_msx = 1'b0;
    reg  [4:0]  sample_level = 5'd0;
    wire [23:0] rgb;

    vu_screen #(.BUILD(`VU_BUILD)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .cx    (cx),
        .cy    (cy),
        .rgb   (rgb),
        .level (level),
        .peak  (peak),
        .st_rom(st_rom),
        .st_msx(st_msx),
        .sample_level(sample_level)
    );

    // ------------------------------------------------------------------
    // Captura: el rgb de ESTE ciclo es el pixel (cx, cy) del ciclo anterior
    // ------------------------------------------------------------------
    reg [23:0] fb [0:HA*VA-1];
    reg [9:0]  cxd = 10'd0;
    reg [9:0]  cyd = 10'd0;
    integer    n_x     = 0;                 // pixeles visibles con X
    integer    n_blank = 0;                 // pixeles de borrado que no son negros
    always @(posedge clk) begin
        cxd <= cx;
        cyd <= cy;
        if (rst_n) begin
            if (cxd < HA && cyd < VA) begin
                fb[cyd*HA + cxd] = rgb;
                if (^rgb === 1'bx) n_x = n_x + 1;
            end
            else if (rgb !== 24'h000000) n_blank = n_blank + 1;
        end
    end

    // ------------------------------------------------------------------
    // Utilidades
    // ------------------------------------------------------------------
    integer errors = 0;
    integer flist;

    // fija las entradas en el borrado vertical y espera un cuadro entero
    task frame;
        input [29:0] lv;
        input [29:0] pv;
        input [1:0]  sr;
        input        sm;
        input [4:0]  sl;
        begin
            wait (cy == 10'd500);
            level  = lv;
            peak   = pv;
            st_rom = sr;
            st_msx = sm;
            sample_level = sl;
            wait (cy == 10'd0);
            wait (cy == 10'd481);
        end
    endtask

    function [23:0] seg_color;              // st: 0 apagado, 1 encendido, 2 pico
        input integer s;
        input integer st;
        begin
            if (s <= 20)      seg_color = (st == 2) ? C_PK_G : (st == 1) ? C_ON_G : C_OFF_G;
            else if (s <= 25) seg_color = (st == 2) ? C_PK_Y : (st == 1) ? C_ON_Y : C_OFF_Y;
            else              seg_color = (st == 2) ? C_PK_R : (st == 1) ? C_ON_R : C_OFF_R;
        end
    endfunction

    // Comprueba las seis barras del cuadro capturado contra level/peak.
    // Muestrea el centro de cada segmento en la fila central (recuento) y
    // ademas en la primera y en la ultima fila de la barra.
    integer n_smp_chk = 0;                  // muestras comprobadas
    integer n_bar_chk = 0;                  // barras comprobadas
    task check_bars;
        integer b, s, r, x, y, lv, pkk, n_on, n_pk, n_off, n_bad, pk_pos, exp_on, exp_pk, st;
        reg [23:0] c;
        begin
            for (b = 0; b < 6; b = b + 1) begin
                lv  = level[5*b +: 5];
                pkk = peak [5*b +: 5];
                n_on = 0; n_pk = 0; n_off = 0; n_bad = 0; pk_pos = 0;
                for (s = 1; s <= 28; s = s + 1) begin
                    x = 168 + (s-1)*18 + 8;
                    // recuento en la fila central
                    c = fb[(bar_y(b) + 12)*HA + x];
                    if      (c === seg_color(s, 1)) n_on  = n_on + 1;
                    else if (c === seg_color(s, 2)) begin n_pk = n_pk + 1; pk_pos = s; end
                    else if (c === seg_color(s, 0)) n_off = n_off + 1;
                    else                            n_bad = n_bad + 1;
                    // cada segmento, uno a uno, en las tres filas
                    st = (pkk != 0 && s == pkk) ? 2 : (s <= lv) ? 1 : 0;
                    for (r = 0; r < 3; r = r + 1) begin
                        y = bar_y(b) + row_dy(r);
                        c = fb[y*HA + x];
                        if (c !== seg_color(s, st)) begin
                            errors = errors + 1;
                            if (errors <= 20)
                                $display("  ERROR barra %0d seg %0d (y=%0d): level=%0d peak=%0d  rgb=%06x, esperado %06x",
                                         b, s, y, lv, pkk, c, seg_color(s, st));
                        end
                        n_smp_chk = n_smp_chk + 1;
                    end
                end
                // recuento: encendidos = level (el segmento del pico cuenta aparte)
                exp_pk = (pkk >= 1 && pkk <= 28) ? 1 : 0;
                exp_on = ((lv > 28) ? 28 : lv) - ((exp_pk == 1 && pkk <= lv) ? 1 : 0);
                if (n_on !== exp_on || n_pk !== exp_pk || n_bad !== 0 ||
                    n_off !== 28 - exp_on - exp_pk || (exp_pk == 1 && pk_pos !== pkk)) begin
                    errors = errors + 1;
                    if (errors <= 20)
                        $display("  ERROR barra %0d: level=%0d peak=%0d -> encendidos=%0d (esperado %0d), picos=%0d en %0d, apagados=%0d, raros=%0d",
                                 b, lv, pkk, n_on, exp_on, n_pk, pk_pos, n_off, n_bad);
                end
                n_bar_chk = n_bar_chk + 1;
            end
        end
    endtask

    // Bordes exactos de cada segmento: 16x24 px, hueco de 2 px, fondo alrededor.
    // Se llama con todo encendido y picos en 28.
    task check_geometry;
        integer b, s, x0, y0, e0;
        reg [23:0] c;
        begin
            e0 = errors;
            for (b = 0; b < 6; b = b + 1) begin
                y0 = bar_y(b);
                for (s = 1; s <= 28; s = s + 1) begin
                    x0 = 168 + (s-1)*18;
                    c  = seg_color(s, (s == 28) ? 2 : 1);
                    // las cuatro esquinas, dentro
                    if (fb[y0*HA + x0] !== c || fb[y0*HA + x0 + 15] !== c ||
                        fb[(y0+23)*HA + x0] !== c || fb[(y0+23)*HA + x0 + 15] !== c)
                        errors = errors + 1;
                    // justo fuera: fondo
                    if (fb[y0*HA + x0 - 1] !== C_BG || fb[y0*HA + x0 + 16] !== C_BG ||
                        fb[y0*HA + x0 + 17] !== C_BG ||
                        fb[(y0-1)*HA + x0] !== C_BG || fb[(y0+24)*HA + x0 + 15] !== C_BG)
                        errors = errors + 1;
                end
            end
            $display("GEOMETRIA: 6 barras x 28 segmentos, esquinas y huecos: %0d errores", errors - e0);
        end
    endtask

    // vuelca el cuadro capturado a PPM (P6) y lo apunta en frames.txt
    task dump;
        input [8*16-1:0] name;
        integer fd, i;
        reg [23:0] c;
        begin
            fd = $fopen(name, "wb");
            $fwrite(fd, "P6\n%0d %0d\n255\n", HA, VA);
            for (i = 0; i < HA*VA; i = i + 1) begin
                c = fb[i];
                $fwrite(fd, "%c%c%c", c[23:16], c[15:8], c[7:0]);
            end
            $fclose(fd);
            $fdisplay(flist, "%0s %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", name,
                      level[4:0], level[9:5], level[14:10], level[19:15], level[24:20], level[29:25],
                      peak[4:0],  peak[9:5],  peak[14:10],  peak[19:15],  peak[24:20],  peak[29:25],
                      st_rom, st_msx, sample_level);
            $display("  volcado %0s", name);
        end
    endtask

    function [29:0] six;                    // empaqueta seis valores de barra
        input integer a0, a1, a2, a3, a4, a5;
        begin
            six = {a5[4:0], a4[4:0], a3[4:0], a2[4:0], a1[4:0], a0[4:0]};
        end
    endfunction

    // ------------------------------------------------------------------
    // Secuencia
    // ------------------------------------------------------------------
    integer     f, b, e0, v;
    reg         full;                       // +completo: todos los cuadros enteros
    reg [173:0] cov_lv;                     // cobertura barra x nivel
    reg [173:0] cov_pk;                     // cobertura barra x pico
    reg [29:0]  lvv;                        // niveles y picos del cuadro siguiente
    reg [29:0]  pkv;

    initial begin
        full  = $test$plusargs("completo");
        flist = $fopen("frames.txt", "w");
        repeat (8) @(posedge clk);
        #1 rst_n = 1'b1;

        // ---- 1. cuadros de muestra ----
        $display("CUADROS DE MUESTRA (barrido completo 858x525)");
        frame(six(0, 0, 0, 0, 0, 0), six(0, 0, 0, 0, 0, 0), 2'd0, 1'b0, 5'd0);
        check_bars;
        dump("vu_a.ppm");

        //          FM L FM R WV L WV R OUT L OUT R
        frame(six(  23,  19,  12,   8,  21,  17),
              six(  26,  22,  16,  13,  25,  20), 2'd1, 1'b1, 5'd14);
        check_bars;
        dump("vu_b.ppm");

        frame(six(28, 28, 28, 28, 28, 28), six(28, 28, 28, 28, 28, 28), 2'd2, 1'b1, 5'd28);
        check_bars;
        check_geometry;
        dump("vu_c.ppm");

        // ---- 2. barrido de niveles, sin pico ----
        fast = !full;
        $display("BARRIDOS: %0s", full ? "cuadros completos (+completo)"
                                       : "solo las 18 lineas que se muestrean por cuadro");
        e0 = errors; cov_lv = 174'd0;
        for (f = 0; f < 29; f = f + 1) begin
            for (b = 0; b < 6; b = b + 1) begin
                v = (f + 5*b) % 29;
                lvv[5*b +: 5] = v[4:0];
                cov_lv[b*29 + v] = 1'b1;
            end
            frame(lvv, 30'd0, f[1:0], f[2], 5'd0);
            check_bars;
        end
        $display("BARRIDO DE NIVELES: 29 cuadros, cobertura barra x nivel %0s, %0d errores",
                 (&cov_lv) ? "174/174" : "INCOMPLETA", errors - e0);
        if (!(&cov_lv)) errors = errors + 1;

        // ---- 3. marca de pico ----
        e0 = errors; cov_pk = 174'd0;
        for (f = 0; f < 29; f = f + 1) begin
            for (b = 0; b < 6; b = b + 1) begin
                v = (f + 5*b) % 29;
                pkv[5*b +: 5] = v[4:0];
                cov_pk[b*29 + v] = 1'b1;
                // nivel: por debajo, a la par y por encima del pico, segun toque
                case ((f + b) % 4)
                    0:       v = (v >= 3) ? v - 3 : 0;
                    1:       v = v;
                    2:       v = (v * 7 + 3*b) % 29;
                    default: v = (v <= 24) ? v + 4 : 28;
                endcase
                lvv[5*b +: 5] = v[4:0];
            end
            frame(lvv, pkv, 2'd1, 1'b1, 5'd0);
            check_bars;
        end
        $display("MARCA DE PICO: 29 cuadros, cobertura barra x pico %0s, %0d errores",
                 (&cov_pk) ? "174/174" : "INCOMPLETA", errors - e0);
        if (!(&cov_pk)) errors = errors + 1;
        fast = 1'b0;

        // ---- 4. valores fuera de rango ----
        e0 = errors;
        frame(six(31, 29, 30, 28, 0, 1), six(29, 31, 30, 0, 28, 1), 2'd3, 1'b0, 5'd0);
        check_bars;
        dump("vu_d.ppm");
        frame(six(5, 31, 14, 27, 20, 26), six(31, 3, 21, 28, 21, 26), 2'd1, 1'b0, 5'd0);
        check_bars;
        dump("vu_e.ppm");
        $display("FUERA DE RANGO: 2 cuadros, %0d errores", errors - e0);

        // ---- resumen ----
        $fclose(flist);
        $display("TOTAL: %0d barras y %0d muestras de segmento comprobadas", n_bar_chk, n_smp_chk);
        $display("PIXELES VISIBLES CON X: %0d", n_x);
        $display("PIXELES DE BORRADO NO NEGROS: %0d", n_blank);
        if (n_x != 0 || n_blank != 0) errors = errors + 1;
        if (errors == 0) $display("RESULTADO: PASS");
        else             $display("RESULTADO: FAIL (%0d errores)", errors);
        $finish;
    end

    // por si algo se queda colgado
    initial begin
        #(37.0 * HT * VT * 80);
        $display("RESULTADO: FAIL (tiempo agotado)");
        $finish;
    end

endmodule

`default_nettype wire

// ============================================================================
// moontang_mix_y8950.v — mezcla del MoonSound con el MSX-Audio (Y8950), solo
// en la variante con Y8950 (moontang_core, Y8950 = 1). (MoonTANG)
//
// El Y8950 es mono: entra igual en L y en R. Su termino es el del MSXimus:
// FM + ADPCM >>> 3 (balance canonico del ADPCM frente a una portadora FM) y x5
// (ganancia del grupo "clasico" del MSXimus frente al OPL4, que entra x1).
//
// LIMITADOR (05/10/2026): con x5, una portadora FM a tope ya da +-20 500 y el
// chip deja margen para 1,6 portadoras (el Y8950 real, para 8): sin limitador,
// un acorde de 3 portadoras a tope (TL = 0) recorta el 60,9 % de las muestras
// contra el raíl (medido en tools/sim/y8950, run.sh mix). A la salida va el
// limitador de rodilla del MSXimus (top.v, sat16k, el mismo que
// alli va detras del mismo x5): unidad hasta 0,75 del fondo de escala (24 576)
// y pendiente 1/2 por encima (2:1), con tope en +-32 767. Por debajo de la
// rodilla no toca nada (una portadora, el ADPCM o una voz wave a tope pasan
// tal cual); por encima comprime tambien al OPL4, como en el MSXimus.
//
// Tres etapas registradas en clk_54m (la ultima, en moontang_core): +2 ciclos
// de 54 MHz de latencia frente a la mezcla sin Y8950, inaudible.
//   1: y_term = (FM + ADPCM>>>3) x5;  mixL3/R3 = sat20(OPL4 + y_term)
//   2: sL/sR/sM = mixL3, mixR3 y (L+R)/2
//   (salida combinacional) knee(sL/sR/sM) -> moontang_core la registra
// ============================================================================
module moontang_mix_y8950 (
    input  wire               clk_54m,
    input  wire signed [17:0] mixL,          // OPL4: FM + wave, lado izquierdo
    input  wire signed [17:0] mixR,
    input  wire signed [15:0] y8950_fm,
    input  wire signed [15:0] y8950_adpcm,
    output wire signed [15:0] out_l,         // ya limitadas (sin registrar)
    output wire signed [15:0] out_r,
    output wire signed [15:0] out_mono,      // (L+R)/2
    // el termino del Y8950 tal como entra en la mezcla, (FM + ADPCM>>>3) x5,
    // saturado a 16 bits: solo para el vumetro (barra MSX-AUDIO de la variante
    // con HDMI). Sin conectar, la sintesis lo quita (no cambia nada mas).
    output wire signed [15:0] out_y
);
    function automatic signed [19:0] sat20(input signed [20:0] v);
        sat20 = (v >  21'sd524287) ? 20'sh7FFFF :
                (v < -21'sd524288) ? 20'sh80000 : v[19:0];
    endfunction

    // rodilla de 24 576 y 2:1 por encima, tope +-32 767 (sat16k del MSXimus)
    localparam signed [20:0] KNEE = 21'sd24576;
    function automatic signed [15:0] knee(input signed [19:0] v);
        reg signed [20:0] vv, a, y;
        begin
            vv = {v[19], v};
            a  = vv[20] ? -vv : vv;                   // |v| <= 524 288: cabe en 21
            y  = (a <= KNEE) ? a : (KNEE + ((a - KNEE) >>> 1));
            if (y > 21'sd32767) y = 21'sd32767;
            knee = vv[20] ? -y[15:0] : y[15:0];
        end
    endfunction

    // ---- etapa 1 ----
    wire signed [15:0] y_adpcm_s = y8950_adpcm >>> 3;
    wire signed [16:0] y_sum = {y8950_fm[15], y8950_fm} + {y_adpcm_s[15], y_adpcm_s};
    reg  signed [19:0] y_term = 20'sd0;               // x5 = x4 + x1 (cabe en 20)
    reg  signed [19:0] mixL3 = 20'sd0, mixR3 = 20'sd0;
    always @(posedge clk_54m) begin
        y_term <= {{3{y_sum[16]}}, y_sum} + {y_sum[16], y_sum, 2'b00};
        mixL3  <= sat20({{3{mixL[17]}}, mixL} + {y_term[19], y_term});
        mixR3  <= sat20({{3{mixR[17]}}, mixR} + {y_term[19], y_term});
    end

    // ---- etapa 2 ----
    wire signed [20:0] mixS = {mixL3[19], mixL3} + {mixR3[19], mixR3};
    reg  signed [19:0] sL = 20'sd0, sR = 20'sd0, sM = 20'sd0;
    always @(posedge clk_54m) begin
        sL <= mixL3;
        sR <= mixR3;
        sM <= mixS[20:1];                             // (L+R)/2
    end

    assign out_y = (y_term >  20'sd32767) ? 16'sh7FFF :
                   (y_term < -20'sd32768) ? 16'sh8000 : y_term[15:0];

    // ---- limitador (lo registra moontang_core) ----
    assign out_l    = knee(sL);
    assign out_r    = knee(sR);
    assign out_mono = knee(sM);
endmodule

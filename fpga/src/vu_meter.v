// ============================================================================
// vu_meter.v — medidor de nivel para el vumetro en pantalla.      (MoonTANG)
//
// Para cada señal de audio (16 bits con signo, dominio clk) guarda el pico de
// |x| durante un cuadro de video y, al llegar el cambio de cuadro, lo pasa a
// SEGMENTOS de barra en escala logaritmica:
//
//     nivel = 4 * (posicion del bit mas alto) + (los dos bits siguientes)
//
// es decir, pasos de ~1,5 dB (6 dB por bit, cuatro pasos por octava; dentro de
// la octava la aproximacion es lineal, de sobra para un vumetro). La barra
// tiene NSEG = 28 segmentos: el de arriba es fondo de escala y el de abajo
// queda 42 dB por debajo.
//
// Balistica (por cuadro, 60 Hz):
//   - la barra sube al instante y cae un segmento cada dos cuadros (~45 dB/s);
//   - la marca de pico se queda HOLD cuadros en su maximo y despues cae igual.
//
// `frame_tog` conmuta una vez por cuadro en el dominio de pixel; aqui se
// sincroniza. Las salidas solo cambian en ese instante (al empezar el borrado
// vertical), asi que el generador de pantalla puede leerlas sin mas cruce: en
// la zona visible llevan milisegundos quietas.
// ============================================================================
`default_nettype none

module vu_meter #(
    parameter integer NCH  = 6,          // numero de señales
    parameter integer HOLD = 45          // cuadros que aguanta la marca de pico
) (
    input  wire                 clk,
    input  wire                 frame_tog,          // conmuta una vez por cuadro
    input  wire [NCH*16-1:0]    samples,            // NCH señales de 16 bits con signo
    output reg  [NCH*5-1:0]     level = {NCH*5{1'b0}},   // segmentos encendidos, 0..28
    output reg  [NCH*5-1:0]     peak  = {NCH*5{1'b0}}    // posicion de la marca, 0 = sin marca
);
    localparam integer NSEG = 28;

    // magnitud (15 bits) -> segmentos 0..28
    function automatic [4:0] segs(input [14:0] m);
        reg [3:0] p;
        reg [1:0] f;
        reg [5:0] lv;
        integer   i;
        begin
            p = 4'd0;
            for (i = 0; i < 15; i = i + 1)
                if (m[i]) p = i[3:0];
            // los dos bits que siguen al mas alto (ceros si no los hay)
            case (p)
                4'd0:    f = 2'b00;
                4'd1:    f = {m[0], 1'b0};
                default: f = {m[p-1], m[p-2]};
            endcase
            lv = {p, f};                                // 0..59
            segs = (lv >= 6'd32) ? (lv - 6'd31) : 5'd0; // 32 -> 1 ... 59 -> 28
        end
    endfunction

    reg [2:0] ft = 3'b000;
    always @(posedge clk) ft <= {ft[1:0], frame_tog};
    wire tick = ft[2] ^ ft[1];

    reg       odd = 1'b0;                // decae un cuadro si y otro no
    always @(posedge clk) if (tick) odd <= ~odd;

    genvar g;
    generate
        for (g = 0; g < NCH; g = g + 1) begin : g_ch
            wire signed [15:0] s   = samples[g*16 +: 16];
            wire        [15:0] neg = -s;
            wire        [14:0] mag = !s[15] ? s[14:0] :
                                     (neg[15] ? 15'h7FFF : neg[14:0]);   // |-32768| satura

            reg [14:0] pk  = 15'd0;      // pico del cuadro en curso
            reg [4:0]  lvl = 5'd0;
            reg [4:0]  hld = 5'd0;
            reg [5:0]  tmr = 6'd0;
            wire [4:0] now = segs(pk);

            always @(posedge clk) begin
                if (tick) begin
                    pk <= mag;
                    // barra
                    if (now >= lvl)                lvl <= now;
                    else if (odd && lvl != 5'd0)   lvl <= lvl - 5'd1;
                    // marca de pico
                    if (now >= hld) begin
                        hld <= now;
                        tmr <= HOLD[5:0];
                    end
                    else if (tmr != 6'd0)          tmr <= tmr - 6'd1;
                    else if (odd && hld != 5'd0)   hld <= hld - 5'd1;
                end
                else if (mag > pk) pk <= mag;

                level[g*5 +: 5] <= lvl;
                peak [g*5 +: 5] <= hld;
            end
        end
    endgenerate
endmodule

`default_nettype wire

// ============================================================================
// i2s_feed.v — entrega de muestras al transmisor I2S sin datos en transito.
//                                                                 (MoonTANG)
// I2S_AUDIO_TX (tnCart) carga SAMPLE_IN en su propio reloj (clk_dac, 1,54 MHz)
// justo en el flanco de LRCLK. Las muestras nacen en clk_54m y cambian a
// 44,1/49,7 kHz: leerlas directamente desde clk_dac capturaba de vez en cuando
// una mezcla de bits de dos muestras consecutivas (un chasquido).
//
// Aqui se sincroniza LRCLK a clk_54m y, nada mas ver su flanco (unos 50 ns
// despues), se deja preparada la muestra de la trama SIGUIENTE en un registro
// que no vuelve a tocarse hasta el proximo flanco de LRCLK: cuando clk_dac la
// lee lleva ~10 us quieta.
//
// Canal: en el instante de carga LRCLK aun lleva el valor del semi-ciclo
// anterior, asi que tras ver LRCLK=1 se prepara L (que saldra con LRCLK=0, el
// canal izquierdo del estandar I2S) y tras ver LRCLK=0 se prepara R.
// Verificado en tools/sim/tb_i2s.v.
// ============================================================================
`default_nettype none

module i2s_feed (
    input  wire               clk,        // clk_54m
    input  wire               lrclk,      // DAC_LRCLK (dominio clk_dac)
    input  wire signed [15:0] samp_l,
    input  wire signed [15:0] samp_r,
    output reg  signed [15:0] sample = 16'sd0
);
    reg [2:0] lr_s = 3'b000;
    always @(posedge clk) begin
        lr_s <= {lr_s[1:0], lrclk};
        if (lr_s[2] ^ lr_s[1]) sample <= lr_s[1] ? samp_l : samp_r;
    end
endmodule

`default_nettype wire

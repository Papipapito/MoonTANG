// ============================================================================
// sigma_delta_dac.v — DAC sigma-delta de 2º orden, 1 bit (MoonTANG)
//
// Convierte una muestra con signo de 16 bits a un bitstream de 1 bit para sacar
// audio por un pin del FPGA (a un filtro RC pasa-bajo -> jack, o al pin SOUND
// del slot). 2º orden para mejor SNR que el 1er orden trivial. Se reloja lo más
// rápido posible (clk_108m) para empujar el ruido de cuantización fuera de la
// banda audible.
// ============================================================================

module sigma_delta_dac (
    input  wire               clk,
    input  wire               rst_n,
    input  wire signed [15:0] din,   // muestra con signo
    output reg                dout   // bitstream 1 bit
);
    // a binario con offset (0x8000 = centro)
    wire [15:0] u = din + 16'sh8000;

    // acumuladores de 2º orden (con margen para no saturar)
    reg  signed [18:0] acc1;
    reg  signed [18:0] acc2;

    wire signed [18:0] fb = dout ? 19'sd32768 : -19'sd32768;
    wire signed [18:0] in_ext = {3'b000, u};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc1 <= 19'sd0;
            acc2 <= 19'sd0;
            dout <= 1'b0;
        end
        else begin
            acc1 <= acc1 + (in_ext - fb);
            acc2 <= acc2 + (acc1   - fb);
            dout <= ~acc2[18];      // signo del 2º integrador
        end
    end
endmodule

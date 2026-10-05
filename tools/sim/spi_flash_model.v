// ============================================================================
// spi_flash_model.v — modelo minimo de flash SPI para simulacion.
//
// Implementa lo justo que usa flash_rw.v: comando READ DATA (0x03) + 24 bits de
// direccion y luego un flujo continuo de bytes. El contenido es una RAMPA: el
// byte de la direccion A vale A[7:0]. Asi cualquier byte duplicado, saltado o
// desplazado en la copia se detecta en el destino.
//
// Opcional: con MEM_SIZE > 0 las direcciones [MEM_BASE, MEM_BASE+MEM_SIZE) salen
// de la matriz `mem` (que el banco rellena por referencia jerarquica), para
// poder servir una imagen sintetica de la YRW801; el resto sigue siendo rampa.
//
// SPI modo 0: el maestro lanza en flanco de BAJADA y muestrea en el de SUBIDA;
// el esclavo hace lo simetrico (saca en BAJADA, captura en SUBIDA).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module spi_flash_model #(
    parameter [23:0] MEM_BASE = 24'h000000,
    parameter integer MEM_SIZE = 0
) (
    input  wire CS,
    input  wire SCLK,
    input  wire MOSI,
    output wire MISO
);
    reg [7:0]  cmd    = 8'h00;
    reg [23:0] addr   = 24'd0;
    reg [5:0]  bitcnt = 6'd0;      // bits recibidos de la cabecera
    reg        phase  = 1'b0;      // 0 = cabecera, 1 = flujo de datos
    reg [23:0] cur    = 24'd0;     // direccion del byte que se esta sirviendo
    reg [2:0]  dbit   = 3'd0;      // indice de bit dentro del byte
    reg [7:0]  osr    = 8'h00;     // registro de desplazamiento de salida
    reg        miso_r = 1'b0;

    assign MISO = CS ? 1'bz : miso_r;

    reg [7:0] mem [0:(MEM_SIZE > 0 ? MEM_SIZE : 1) - 1];
    wire [23:0] moff = cur - MEM_BASE;
    wire        in_mem = (MEM_SIZE > 0) && (cur >= MEM_BASE) && (moff < MEM_SIZE);
    wire [7:0]  cur_byte = in_mem ? mem[moff] : cur[7:0];

    always @(posedge CS) begin
        bitcnt <= 6'd0;
        phase  <= 1'b0;
        dbit   <= 3'd0;
        cmd    <= 8'h00;
    end

    // ---- captura de la cabecera (comando + direccion) ----
    always @(posedge SCLK) begin
        if (!CS && !phase) begin
            if (bitcnt < 6'd8)  cmd  <= {cmd[6:0],  MOSI};
            else                addr <= {addr[22:0], MOSI};
            if (bitcnt == 6'd31) begin
                // ultima captura de direccion: preparar el flujo
                phase <= 1'b1;
                dbit  <= 3'd0;
                cur   <= {addr[22:0], MOSI};   // la direccion recien completada
            end
            bitcnt <= bitcnt + 6'd1;
        end
    end

    // ---- serializacion de los datos ----
    always @(negedge SCLK) begin
        if (!CS && phase) begin
            if (dbit == 3'd0) begin
                // byte nuevo: imagen en memoria o RAMPA (addr[7:0])
                miso_r <= cur_byte[7];
                osr    <= {cur_byte[6:0], 1'b0};
                cur    <= cur + 24'd1;
            end
            else begin
                miso_r <= osr[7];
                osr    <= {osr[6:0], 1'b0};
            end
            dbit <= dbit + 3'd1;    // se envuelve solo cada 8
        end
    end
endmodule

`default_nettype wire

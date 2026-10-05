// ============================================================================
// smd_board.v — modelo del cartucho MSXhdmi_tn20k_smd (rev B) + Tang Nano 20K,
//               visto desde los PINES de la FPGA (encapsulado QN88).
//
// De donde sale cada cosa:
//   - que señal del slot va a que pin de FPGA: smd_pcb_pins.vh, generado de la
//     PCB real de KiCad siguiendo el cobre a traves de los 74LVC245
//     (gen_smd_pins.py). El generador comprueba ademas que /WAIT, /INT, /M1,
//     /BUSDIR y SOUNDIN NO llegan a la FPGA y como estan cableados DIR y /OE.
//   - U1, U2, U4 (direcciones y control): DIR a 3V3, /OE a masa: solo conducen
//     del MSX a la FPGA.
//   - U3 (datos): /OE a masa (siempre conduce hacia un lado) y DIR en el pin
//     DATADIR con R1 de 10k a 3V3:  DIR = 1 -> MSX -> FPGA,  DIR = 0 -> FPGA -> MSX.
//   - flash SPI y cristal: los del modulo Tang (pines 59-62 y 4).
//
// Los retardos que el RTL no tiene (reloj->pad de la FPGA, propagacion y giro
// de los buffers) se añaden aqui.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module smd_board #(
    parameter real T_FPGA_CO = 4.0,     // reloj -> pad de la FPGA
    parameter real T_BUF_PD  = 4.0,     // propagacion del 74LVC245
    parameter real T_BUF_DIR = 6.0      // tiempo de giro (deshabilitar un lado / habilitar el otro)
) (
    inout  wire [88:1] pin,

    // ---- conector de cartucho (lo que SI esta cableado) ----
    input  wire [15:0] s_a,
    inout  wire [7:0]  s_d,
    input  wire        s_mreq_n, s_iorq_n, s_rd_n, s_wr_n, s_reset_n,
    input  wire        s_sltsl_n, s_clock,

    output wire        cart_drives_d,   // U3 esta conduciendo D0-D7 hacia el MSX
    output wire        j2_1,            // zocalo ESP-01S, pad 1
    output wire        j2_8             // zocalo ESP-01S, pad 8
);
`include "smd_pcb_pins.vh"
    localparam P_CLK = 4, P_MSPI_SCLK = 59, P_MSPI_CS = 60, P_MSPI_MOSI = 61, P_MSPI_MISO = 62;

    // ---- cristal de 27 MHz de la Tang ----
    reg clk27 = 1'b0;
    always #18.5185 clk27 = ~clk27;
    assign pin[P_CLK] = clk27;

    // ---- U1 y U2: direcciones, solo MSX -> FPGA ----
    assign #(T_BUF_PD) pin[P_A0]  = s_a[0];
    assign #(T_BUF_PD) pin[P_A1]  = s_a[1];
    assign #(T_BUF_PD) pin[P_A2]  = s_a[2];
    assign #(T_BUF_PD) pin[P_A3]  = s_a[3];
    assign #(T_BUF_PD) pin[P_A4]  = s_a[4];
    assign #(T_BUF_PD) pin[P_A5]  = s_a[5];
    assign #(T_BUF_PD) pin[P_A6]  = s_a[6];
    assign #(T_BUF_PD) pin[P_A7]  = s_a[7];
    assign #(T_BUF_PD) pin[P_A8]  = s_a[8];
    assign #(T_BUF_PD) pin[P_A9]  = s_a[9];
    assign #(T_BUF_PD) pin[P_A10] = s_a[10];
    assign #(T_BUF_PD) pin[P_A11] = s_a[11];
    assign #(T_BUF_PD) pin[P_A12] = s_a[12];
    assign #(T_BUF_PD) pin[P_A13] = s_a[13];
    assign #(T_BUF_PD) pin[P_A14] = s_a[14];
    assign #(T_BUF_PD) pin[P_A15] = s_a[15];

    // ---- U4: control, solo MSX -> FPGA ----
    assign #(T_BUF_PD) pin[P_MREQ_N]  = s_mreq_n;
    assign #(T_BUF_PD) pin[P_IORQ_N]  = s_iorq_n;
    assign #(T_BUF_PD) pin[P_RD_N]    = s_rd_n;
    assign #(T_BUF_PD) pin[P_WR_N]    = s_wr_n;
    assign #(T_BUF_PD) pin[P_RESET_N] = s_reset_n;
    assign #(T_BUF_PD) pin[P_CLOCK]   = s_clock;
    assign #(T_BUF_PD) pin[P_SLTSL_N] = s_sltsl_n;

    // ---- U3: datos, /OE a masa, DIR = DATADIR con R1 a 3V3 ----
    // (con la FPGA sin configurar el pin esta en alta impedancia y manda R1)
    wire dir_pin = (pin[P_DATADIR] === 1'b0) ? 1'b0 : 1'b1;
    wire dir_d;
    assign #(T_FPGA_CO + T_BUF_DIR) dir_d = dir_pin;
    wire [7:0] d_fpga = {pin[P_D7], pin[P_D6], pin[P_D5], pin[P_D4],
                         pin[P_D3], pin[P_D2], pin[P_D1], pin[P_D0]};
    wire [7:0] to_fpga, to_slot;
    assign #(T_BUF_PD)             to_fpga = s_d;
    assign #(T_FPGA_CO + T_BUF_PD) to_slot = d_fpga;

    assign pin[P_D0] = dir_d ? to_fpga[0] : 1'bz;
    assign pin[P_D1] = dir_d ? to_fpga[1] : 1'bz;
    assign pin[P_D2] = dir_d ? to_fpga[2] : 1'bz;
    assign pin[P_D3] = dir_d ? to_fpga[3] : 1'bz;
    assign pin[P_D4] = dir_d ? to_fpga[4] : 1'bz;
    assign pin[P_D5] = dir_d ? to_fpga[5] : 1'bz;
    assign pin[P_D6] = dir_d ? to_fpga[6] : 1'bz;
    assign pin[P_D7] = dir_d ? to_fpga[7] : 1'bz;
    assign s_d = dir_d ? 8'hzz : to_slot;
    assign cart_drives_d = ~dir_d;

    // ---- zocalo del ESP-01S (con las resistencias a masa del modulo Tang) ----
    assign (weak0, weak1) pin[P_J2_1] = 1'b0;
    assign (weak0, weak1) pin[P_J2_8] = 1'b0;
    assign j2_1 = pin[P_J2_1];
    assign j2_8 = pin[P_J2_8];

    // ---- flash SPI de la Tang, con la imagen de la YRW801 en 0x200000 ----
    spi_flash_model #(.MEM_BASE(24'h200000), .MEM_SIZE(65536)) u_flash (
        .CS(pin[P_MSPI_CS]), .SCLK(pin[P_MSPI_SCLK]),
        .MOSI(pin[P_MSPI_MOSI]), .MISO(pin[P_MSPI_MISO])
    );
endmodule

`default_nettype wire

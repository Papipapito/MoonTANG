// ============================================================================
// wt20x_board.v — modelo de la placa WonderTANG 2.0b / 2.02b + Tang Nano 20K,
//                 visto desde los PINES de la FPGA (encapsulado QN88).
//
// De donde sale cada cosa (nada es de cosecha propia):
//   - numeros de pin: wt_official_pins.vh, generado del top.cst del firmware
//     oficial (lfantoniosi/WonderTANG, y new-juice para las 2.02b: coinciden).
//   - multiplexado del bus (top.v oficial, "DOT STATE"):
//        msel_n[0] a 0 -> mp[7:0] = A0-A7
//        msel_n[1] a 0 -> mp[7:0] = A8-A15
//        msel_n[2] a 0 -> mp = {M1, CS12, RFSH, RESET, CS2, CS1, IORQ, MERQ}
//   - datos: transceptor con DIR = datadir (1 = MSX -> FPGA).
//   - /WAIT e /INT: transistores NPN en colector abierto -> el pin a 1 ASERTA
//     la linea del slot (top.v oficial: int_n = ~vdp_irq_n; wait_n = ff_wait).
//   - /BUSDIR: directo.
//   - audio: amplificador I2S MONO de la Tang (MAX98357A) cuya salida va por J3
//     al SOUNDIN del slot. Con PA_EN a 1 reproduce el canal IZQUIERDO.
//
// Los retardos que el RTL no tiene (reloj->pad de la FPGA, habilitacion de los
// buffers, pad->registro) se añaden aqui para que el barrido de multiplexado se
// pruebe con la holgura real y no con una ideal.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module wt20x_board #(
    parameter real T_FPGA_CO = 4.0,     // reloj -> pad de la FPGA
    parameter real T_BUF_EN  = 6.0,     // tPZx / tPxZ de los buffers
    parameter real T_BUF_PD  = 4.0,     // propagacion de los buffers
    parameter real T_FPGA_IN = 1.5,     // pad -> registro de la FPGA
    parameter real T_NPN_ON  = 60.0,    // el NPN entra en conduccion
    parameter real T_NPN_OFF = 300.0    // sale de saturacion + pull-up del MSX
) (
    inout  wire [88:1] pin,

    // ---- conector de cartucho ----
    input  wire [15:0] s_a,
    inout  wire [7:0]  s_d,
    input  wire        s_mreq_n, s_iorq_n, s_rd_n, s_wr_n, s_reset_n,
    input  wire        s_m1_n, s_rfsh_n, s_cs1_n, s_cs2_n, s_cs12_n,
    input  wire        s_sltsl_n, s_clock,
    output wire        s_wait_n,        // colector abierto: 0 o Z
    output wire        s_int_n,         // colector abierto: 0 o Z
    output wire        s_busdir_n,

    // ---- lo que oye el MSX por SOUNDIN (salida del ampli mono) ----
    output reg signed [15:0] spk = 16'sd0,
    output reg signed [15:0] i2s_l = 16'sd0,
    output reg signed [15:0] i2s_r = 16'sd0,
    output reg         i2s_frame = 1'b0,    // conmuta con cada trama completa
    output wire        led,
    output wire        cart_drives_d        // la placa esta conduciendo D0-D7
);
`include "wt_official_pins.vh"

    // ------------------------------------------------------------------
    //  Cristal de 27 MHz de la Tang
    // ------------------------------------------------------------------
    reg clk27 = 1'b0;
    always #18.5185 clk27 = ~clk27;
    assign pin[P_CLK] = clk27;

    // ------------------------------------------------------------------
    //  Bus multiplexado: tres buffers sobre mp[7:0]
    // ------------------------------------------------------------------
    wire [2:0] msel_pin = {pin[P_MSEL_N2], pin[P_MSEL_N1], pin[P_MSEL_N0]};
    wire [2:0] msel_a, msel_b;
    assign #(T_FPGA_CO) msel_a = msel_pin;      // sale de la FPGA
    assign #(T_BUF_EN)  msel_b = msel_a;        // el buffer termina de conmutar
    wire settling = (msel_a !== msel_b);

    wire [15:0] a_b;
    wire [7:0]  ctl_b;
    assign #(T_BUF_PD) a_b   = s_a;
    assign #(T_BUF_PD) ctl_b = {s_m1_n, s_cs12_n, s_rfsh_n, s_reset_n,
                                s_cs2_n, s_cs1_n, s_iorq_n, s_mreq_n};

    wire [1:0] n_en = (msel_b[0] === 1'b0) + (msel_b[1] === 1'b0) + (msel_b[2] === 1'b0);
    wire [7:0] mp_bus = settling             ? 8'hxx :
                        (n_en > 2'd1)        ? 8'hxx :      // dos buffers a la vez
                        (msel_b[0] === 1'b0) ? a_b[7:0]  :
                        (msel_b[1] === 1'b0) ? a_b[15:8] :
                        (msel_b[2] === 1'b0) ? ctl_b     : 8'hzz;
    wire [7:0] mp_in;
    assign #(T_FPGA_IN) mp_in = mp_bus;
    assign pin[P_MP0] = mp_in[0];
    assign pin[P_MP1] = mp_in[1];
    assign pin[P_MP2] = mp_in[2];
    assign pin[P_MP3] = mp_in[3];
    assign pin[P_MP4] = mp_in[4];
    assign pin[P_MP5] = mp_in[5];
    assign pin[P_MP6] = mp_in[6];
    assign pin[P_MP7] = mp_in[7];

    // ------------------------------------------------------------------
    //  Señales directas
    // ------------------------------------------------------------------
    assign #(T_BUF_PD) pin[P_SLTSL_N] = s_sltsl_n;
    assign #(T_BUF_PD) pin[P_RD_N]    = s_rd_n;
    assign #(T_BUF_PD) pin[P_WR_N]    = s_wr_n;
    assign #(T_BUF_PD) pin[P_CLOCK]   = s_clock;

    // ------------------------------------------------------------------
    //  Datos: transceptor con DIR = datadir (1 = MSX -> FPGA)
    // ------------------------------------------------------------------
    wire dir_d;
    assign #(T_FPGA_CO + T_BUF_EN) dir_d = pin[P_DATADIR];
    wire [7:0] cd_pin = {pin[P_CD7], pin[P_CD6], pin[P_CD5], pin[P_CD4],
                         pin[P_CD3], pin[P_CD2], pin[P_CD1], pin[P_CD0]};
    wire [7:0] to_fpga, to_slot;
    assign #(T_BUF_PD) to_fpga = s_d;
    assign #(T_FPGA_CO + T_BUF_PD) to_slot = cd_pin;

    assign pin[P_CD0] = (dir_d === 1'b1) ? to_fpga[0] : 1'bz;
    assign pin[P_CD1] = (dir_d === 1'b1) ? to_fpga[1] : 1'bz;
    assign pin[P_CD2] = (dir_d === 1'b1) ? to_fpga[2] : 1'bz;
    assign pin[P_CD3] = (dir_d === 1'b1) ? to_fpga[3] : 1'bz;
    assign pin[P_CD4] = (dir_d === 1'b1) ? to_fpga[4] : 1'bz;
    assign pin[P_CD5] = (dir_d === 1'b1) ? to_fpga[5] : 1'bz;
    assign pin[P_CD6] = (dir_d === 1'b1) ? to_fpga[6] : 1'bz;
    assign pin[P_CD7] = (dir_d === 1'b1) ? to_fpga[7] : 1'bz;
    assign s_d = (dir_d === 1'b0) ? to_slot : 8'hzz;
    assign cart_drives_d = (dir_d === 1'b0);

    // ------------------------------------------------------------------
    //  /WAIT e /INT por NPN (pin a 1 = linea aserta); /BUSDIR directo
    // ------------------------------------------------------------------
    wire #(T_NPN_ON, T_NPN_OFF) wait_on = (pin[P_WAIT_N] === 1'b1);
    wire #(T_NPN_ON, T_NPN_OFF) int_on  = (pin[P_INT_N]  === 1'b1);
    assign s_wait_n = wait_on ? 1'b0 : 1'bz;
    assign s_int_n  = int_on  ? 1'b0 : 1'bz;
    assign #(T_FPGA_CO) s_busdir_n = pin[P_BUSDIR_N];

    assign led = pin[P_LED];

    // ------------------------------------------------------------------
    //  Amplificador I2S de la Tang (MAX98357A). Captura en flanco de subida
    //  de BCLK; el MSB va UN BCLK despues del flanco de LRCLK; LRCLK=0 = L.
    // ------------------------------------------------------------------
    wire bclk = pin[P_HP_BCK];
    wire ws   = pin[P_HP_WS];
    wire sdin = pin[P_HP_DIN];
    reg        ws_q = 1'b0;
    reg [4:0]  nbit = 5'd31;
    reg [15:0] sh = 16'd0;
    reg        ch = 1'b0;
    always @(posedge bclk) begin
        ws_q <= ws;
        if (ws !== ws_q) begin
            // Flanco de LRCLK. El bit 16 de la palabra anterior (su LSB) coincide
            // con este mismo flanco: se cierra aqui la palabra en curso.
            if (nbit == 5'd15) begin
                if (ch === 1'b0) i2s_l <= {sh[14:0], sdin};
                else begin
                    i2s_r     <= {sh[14:0], sdin};
                    i2s_frame <= ~i2s_frame;
                end
            end
            nbit <= 5'd0;               // el siguiente bit es el MSB de la nueva
            ch   <= ws;
        end
        else if (nbit < 5'd15) begin
            sh   <= {sh[14:0], sdin};
            nbit <= nbit + 5'd1;
        end
    end
    // PA_EN a 1 (SD_MODE alto) -> el chip reproduce el canal izquierdo.
    always @(i2s_frame) spk = (pin[P_PA_EN] === 1'b1) ? i2s_l : 16'sd0;

    // ------------------------------------------------------------------
    //  Flash SPI de la Tang, con la imagen de la YRW801 en 0x200000
    // ------------------------------------------------------------------
    spi_flash_model #(.MEM_BASE(24'h200000), .MEM_SIZE(65536)) u_flash (
        .CS(pin[P_MSPI_CS]), .SCLK(pin[P_MSPI_SCLK]),
        .MOSI(pin[P_MSPI_MOSI]), .MISO(pin[P_MSPI_MISO])
    );
endmodule

`default_nettype wire

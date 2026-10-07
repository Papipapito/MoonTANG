// ============================================================================
// moontang_y8950.sv — el Y8950 (MSX-Audio) junto al MoonSound, en C0h-C1h.
//
// Es el MSX-Audio del MSXimus (60K, rama V3.8), sin cambios en sus piezas:
//   FM      jtopl2 (jotego, GPL-3, OPL_TYPE = 2, salida mono)
//   ADPCM   y8950_adpcm (MSXimus) + jt10_adpcmb / jt10_adpcmb_interpol (jotego)
//   RAM     adpcm_sdram (MSXimus): los 256 KB de muestras del Y8950 en la
//           SDRAM (bancos 2-3), como segundo cliente de wv_to_sdram
// Aqui solo va el pegamento con el nucleo:
//   - El bus (ya en clk_54m) se registra UNA vez y se decodifica igual que en
//     opl4fm (C4h-C7h): misma etapa, mismas condiciones (IORQ, M1 = 1), asi que
//     las lecturas de C0h/C1h salen por rd_data con la misma temporizacion que
//     las del OPL4. Sin /WAIT (el chip real tampoco lo usa).
//   - Escrituras: se toman en el PRIMER ciclo en que se ve la escritura (como
//     las shadow del OPL3 en opl4fm), con el dato de ese ciclo. jtopl escribe
//     por nivel en cada flanco de clk mientras le dura cs_n; en el MSXimus se
//     le daba el ciclo de bus entero, pero aqui el front-end de la WonderTANG
//     retrasa /WR 83 ns (para alinearlo con /IORQ y la direccion, que llegan
//     por el bus multiplexado) y el dato NO: al final del OUT, jtopl veia
//     durante unos ciclos el bus ya suelto (FFh) y se quedaba con el (medido en
//     el banco de placa: el registro seleccionado acababa en FFh y la nota no
//     sonaba). Por eso jtopl recibe un pulso de 2 ciclos con el dato y A0 del
//     primer ciclo guardados; el ADPCM, el pulso de 1 ciclo de siempre. Asi da
//     igual cuanto dure /WR y cuando suelte el MSX el bus de datos. (Control
//     negativo 5 de tools/sim/board/run_board.sh todo: con el ciclo entero,
//     jtopl se queda FFh como indice o como dato en algunas de las 105 fases
//     del Z80 frente a la FPGA (fase L4b del banco); segun en cual caigan las
//     escrituras, la nota FM de la fase L4 suena o no.)
//   - Lectura de C1h: un pulso por IN (los efectos laterales del registro 0Fh,
//     una vez). Se saca de las señales de entrada, un ciclo ANTES de la etapa
//     registrada: el dato de C1h se actualiza en el mismo flanco en que sube
//     rd y esta listo desde el primer ciclo de la lectura, como el de C0h
//     (combinacional) y los del OPL4. Asi aguanta lo mismo con turbo.
//   - Reloj: clk_54m con un CE de 35/528 = 3,579545 MHz exactos (315/88 MHz);
//     el MSXimus usa 3,6 MHz (54/15). Ninguna red de reloj nueva.
//   - IRQ: la compuesta del Y8950 (timers + EOS + BUF_RDY, cada una con su
//     mascara del registro 4), activa a nivel bajo. Arranca enmascarada. A
//     diferencia de lo que dice la cabecera de la copia de y8950_adpcm.v
//     ("IRQ ... SIN cablear al /INT", que es lo del MSXimus), en MoonTANG la
//     salida irq si se cablea: int_n va al /INT del slot (en AND con la del
//     OPL3, en moontang_core).
// ============================================================================

`default_nettype none

module moontang_y8950 (
    input  wire        clk_54m,
    input  wire        clk_108m,
    input  wire        rst_n,           // bus_reset_n (sigue al /RESET del slot)

    // ---- bus del MSX, en clk_54m (las mismas señales que recibe opl4fm) ----
    input  wire        iorq_n,
    input  wire        rd_n,
    input  wire        wr_n,
    input  wire        m1_n,
    input  wire [7:0]  addr,
    input  wire [7:0]  din,

    output wire        rd,              // lectura de C0h/C1h en curso
    output wire [7:0]  dout,            // dato de esa lectura
    output wire        int_n,           // IRQ del Y8950 (0 = activa)

    // ---- audio, en clk_54m ----
    output wire signed [15:0] fm,       // jtopl2
    output wire signed [15:0] adpcm,    // ADPCM-B ya con su volumen (reg 12h)

    // ---- RAM de muestras: cliente wv2 de wv_to_sdram (clk_108m) ----
    output wire        wv2_req,
    output wire        wv2_we,
    output wire [21:0] wv2_addr,
    output wire [7:0]  wv2_wdata,
    input  wire [15:0] wv2_dout,
    input  wire        wv2_done
);

    // ------------------------------------------------------------------
    //  CE de 3,579545 MHz: 54 MHz x 35/528
    // ------------------------------------------------------------------
    reg [9:0] ce_acc = 10'd0;
    reg       cen = 1'b0;
    always @(posedge clk_54m) begin
        if (ce_acc >= 10'd493) begin ce_acc <= ce_acc - 10'd493; cen <= 1'b1; end
        else                   begin ce_acc <= ce_acc + 10'd35;  cen <= 1'b0; end
    end

    // ------------------------------------------------------------------
    //  Bus registrado y decodificacion (como opl4fm)
    // ------------------------------------------------------------------
    reg       iorq_r = 1'b1, rd_r = 1'b1, wr_r = 1'b1, m1_r = 1'b1;
    reg [7:0] addr_r = 8'd0, din_r = 8'd0;
    always @(posedge clk_54m) begin
        iorq_r <= iorq_n; rd_r <= rd_n; wr_r <= wr_n; m1_r <= m1_n;
        addr_r <= addr;   din_r <= din;
    end

    wire cs       = !iorq_r && m1_r && (addr_r[7:1] == 7'b1100000);    // C0h-C1h
    wire wr_act   = cs && !wr_r;
    wire rd_act   = cs && !rd_r;
    assign rd     = rd_act;

    reg  wr_prev = 1'b0;
    always @(posedge clk_54m) wr_prev <= wr_act;
    wire wr_c0 = wr_act && !wr_prev && !addr_r[0];
    wire wr_c1 = wr_act && !wr_prev &&  addr_r[0];

    wire rd1_now  = !iorq_n && m1_n && !rd_n && (addr == 8'hC1);   // sin registrar
    reg  rd1_prev = 1'b0;
    always @(posedge clk_54m) rd1_prev <= rd1_now;
    wire rd_c1 = rd1_now && !rd1_prev;

    // ------------------------------------------------------------------
    //  FM: jtopl2
    // ------------------------------------------------------------------
    reg       jt_wr = 1'b0, jt_wr2 = 1'b0, jt_a0 = 1'b0;
    reg [7:0] jt_din = 8'd0;
    always @(posedge clk_54m) begin
        if (wr_act && !wr_prev) begin
            jt_din <= din_r;
            jt_a0  <= addr_r[0];
        end
        jt_wr  <= wr_act && !wr_prev;
        jt_wr2 <= jt_wr;
    end

    wire [7:0] jt_dout;
    jtopl2 u_fm (
        .rst(~rst_n), .clk(clk_54m), .cen(cen),
        .din(jt_din), .addr(jt_a0), .cs_n(~(jt_wr | jt_wr2)), .wr_n(1'b0),
        .dout(jt_dout), .irq_n(), .snd(fm), .sample()
    );

    // ------------------------------------------------------------------
    //  ADPCM-B
    // ------------------------------------------------------------------
    wire [7:0]  st_c0, dat_c1, mem_diag;
    wire        irq;
    wire        m_req_t, m_we, m_done_t;
    wire [17:0] m_addr;
    wire [7:0]  m_wdata;
    wire [15:0] m_rword;

    y8950_adpcm u_adpcm (
        .clk(clk_54m), .cen3m6(cen), .rst_n(rst_n),
        .wr_c0(wr_c0), .wr_c1(wr_c1), .rd_c1(rd_c1), .din(din_r),
        .ft1(jt_dout[6]), .ft2(jt_dout[5]),
        .status(st_c0), .data_dout(dat_c1), .irq(irq), .pcm_out(adpcm),
        .mem_req_t(m_req_t), .mem_we(m_we), .mem_addr(m_addr), .mem_wdata(m_wdata),
        .mem_rword(m_rword), .mem_done_t(m_done_t), .mem_diag(mem_diag)
    );

    adpcm_sdram #(.FALLBACK_BSRAM(0)) u_ram (
        .clk_host(clk_54m), .rst_n(rst_n),
        .req_toggle(m_req_t), .we(m_we), .addr(m_addr), .wdata(m_wdata),
        .rword(m_rword), .done_toggle(m_done_t),
        .clk_108m(clk_108m),
        .wv_req(wv2_req), .wv_we(wv2_we), .wv_addr(wv2_addr), .wv_wdata(wv2_wdata),
        .wv_dout(wv2_dout), .wv_done(wv2_done)
    );

    assign dout  = addr_r[0] ? dat_c1 : st_c0;
    assign int_n = ~irq;

endmodule

`default_nettype wire

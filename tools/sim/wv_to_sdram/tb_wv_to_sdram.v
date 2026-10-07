// ============================================================================
// tb_wv_to_sdram.v — banco unitario del puente wv_to_sdram (dos clientes,
//                    refresco y watchdog) contra un controlador de SDRAM FALSO
//                    que se puede atascar a voluntad.
//
// Que comprueba (ver run.sh):
//   (a) el watchdog salta durante un REFRESCO con una peticion pendiente: la
//       peticion se sirve en cuanto el controlador vuelve (con el puente de
//       5400f15 se queda colgada para siempre: control negativo).
//   (b) el watchdog salta en ACCEPT, RD y WR para cada cliente: el done y el
//       dato FFFFh van SOLO al dueño de la operacion; el otro cliente no recibe
//       ningun done de mas, su operacion se sirve despues con su dato bueno, y
//       el dueño sigue funcionando.
//   (c) prioridades (refresco > wv > wv2) y que wv2 no se muere de hambre con
//       el cliente 1 saturado al ritmo maximo de wave_sdram.
//   (d) mapeo: el cliente 1 va a los bancos 0-1 (bus_address[22] = 0) y el 2 a
//       los bancos 2-3 (bus_address[22] = 1), sin alias entre los dos, con la
//       lane de byte correcta.
//   (e) trafico aleatorio de los dos clientes con el refresco en marcha: datos,
//       ritmo de refresco, ninguna orden ilegal y el watchdog sin saltar.
//   (f) operacion ABORTADA: el cliente baja su req a mitad (un /RESET del MSX
//       resetea adpcm_sdram pero no el puente) y vuelve a pedir enseguida: el
//       done de la operacion abortada no se entrega, y la peticion nueva recibe
//       el suyo con su dato (en RD, en WR y en ACCEPT colgado hasta el watchdog).
//   (g) el watchdog no cuenta en ST_IDLE: un init del controlador de 5000 ciclos
//       (bus_ready = 0, puente en reposo) no lo hace saltar en el primer refresco.
//
// Con -DNEG_HEAD se compila contra el puente de 5400f15 (un solo cliente):
// solo se ejecutan las partes del cliente 1 y (a) TIENE que fallar.
// run.sh tiene ademas dos mutantes del puente actual (sin el arreglo de (f) y
// sin el de (g)) que TIENEN que fallar.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

// ----------------------------------------------------------------------------
//  Controlador de SDRAM falso: mismo contrato que ip_sdram (bus_valid /
//  bus_refresh se muestrean con bus_ready = 1; ready cae el ciclo siguiente y
//  vuelve a subir al terminar; la lectura da bus_rdata_en un ciclo).
// ----------------------------------------------------------------------------
module fake_sdram_ctrl #(
    parameter integer RD_LAT  = 7,
    parameter integer WR_LAT  = 6,
    parameter integer REF_LAT = 9
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [22:2] bus_address,
    input  wire        bus_valid,
    input  wire        bus_write,
    input  wire        bus_refresh,
    input  wire [31:0] bus_wdata,
    input  wire [3:0]  bus_wdata_mask,
    output reg  [31:0] bus_rdata = 32'd0,
    output reg         bus_rdata_en = 1'b0,
    output reg         bus_ready = 1'b0
);
    reg [31:0] mem [0:2097151];             // 8 MB: 4 bancos de 2 MB

    // ---- inyeccion de fallos (la pone el banco) ----
    // modo 1: ignorar la siguiente orden de ese tipo (ready sigue a 1: ACCEPT colgado)
    // modo 2: aceptarla y colgarse inj_cycles ciclos con ready = 0, sin dato ni escritura
    // modo 3: aceptarla y tardar inj_cycles ciclos en hacerla (lenta, pero bien)
    integer inj_mode = 0;
    integer inj_kind = 0;                   // 0 lectura, 1 escritura, 2 refresco
    integer inj_cycles = 0;
    integer init_cyc = 5000;                // (g): init largo con el puente en reposo

    integer n_rd = 0, n_wr = 0, n_ref = 0, n_ign = 0, n_err = 0;
    integer n_log = 0;
    reg [1:0]  log_kind [0:262143];
    reg [22:2] log_addr [0:262143];
    integer    log_cyc  [0:262143];
    integer    cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    localparam S_INIT = 0, S_IDLE = 1, S_BUSY = 2, S_STUCK = 3;
    integer    st = S_INIT, cnt = 5000, kind;
    reg [22:2] a_q;
    reg        is_rd;
    integer    k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_INIT; cnt <= init_cyc; bus_ready <= 1'b0; bus_rdata_en <= 1'b0;
        end
        else begin
            bus_rdata_en <= 1'b0;
            if ((bus_valid || bus_refresh) && !bus_ready) begin
                n_err = n_err + 1;
                $display("  [ERR ctrl %0t] orden con bus_ready = 0", $time);
            end
            if (bus_valid && bus_refresh) begin
                n_err = n_err + 1;
                $display("  [ERR ctrl %0t] bus_valid y bus_refresh a la vez", $time);
            end
            case (st)
            S_INIT: begin
                cnt <= cnt - 1;
                if (cnt == 0) begin bus_ready <= 1'b1; st <= S_IDLE; end
            end
            S_IDLE: if (bus_ready && (bus_valid || bus_refresh)) begin
                kind = bus_refresh ? 2 : (bus_write ? 1 : 0);
                log_kind[n_log] = kind[1:0];
                log_addr[n_log] = bus_address;
                log_cyc[n_log]  = cyc;
                n_log = n_log + 1;
                if (inj_mode == 1 && inj_kind == kind) begin
                    inj_mode = 0;               // se ignora: ready sigue a 1
                    n_ign = n_ign + 1;
                end
                else if (inj_mode == 2 && inj_kind == kind) begin
                    inj_mode = 0;
                    bus_ready <= 1'b0;
                    cnt <= inj_cycles;
                    st  <= S_STUCK;
                end
                else begin
                    if (kind == 0) n_rd = n_rd + 1;
                    if (kind == 1) begin
                        n_wr = n_wr + 1;
                        for (k = 0; k < 4; k = k + 1)
                            if (!bus_wdata_mask[k]) mem[bus_address][8*k +: 8] = bus_wdata[8*k +: 8];
                    end
                    if (kind == 2) n_ref = n_ref + 1;
                    a_q   = bus_address;
                    is_rd = (kind == 0);
                    bus_ready <= 1'b0;
                    if (inj_mode == 3 && inj_kind == kind) begin
                        inj_mode = 0;
                        cnt <= inj_cycles;
                    end
                    else cnt <= (kind == 0) ? RD_LAT : (kind == 1) ? WR_LAT : REF_LAT;
                    st <= S_BUSY;
                end
            end
            S_BUSY: begin
                cnt <= cnt - 1;
                if (cnt == 2 && is_rd) begin bus_rdata <= mem[a_q]; bus_rdata_en <= 1'b1; end
                if (cnt == 0) begin bus_ready <= 1'b1; st <= S_IDLE; end
            end
            S_STUCK: begin
                cnt <= cnt - 1;
                if (cnt == 0) begin bus_ready <= 1'b1; st <= S_IDLE; end
            end
            endcase
        end
    end
endmodule

// ----------------------------------------------------------------------------
//  Cliente con el contrato de 4 fases y la temporizacion de wave_sdram /
//  adpcm_sdram: baja req en el flanco en que ve el done, un ciclo de guarda
//  (ST_DROP) y en el siguiente ST_IDLE ya puede pedir otra (GAP = 1).
// ----------------------------------------------------------------------------
module wv_client #(parameter integer GAP = 1) (
    input  wire        clk,
    input  wire        rst_n,
    output reg         req = 1'b0,
    output reg         we = 1'b0,
    output reg  [21:0] addr = 22'd0,
    output reg  [7:0]  wdata = 8'd0,
    input  wire [15:0] dout,
    input  wire        done
);
    localparam integer QN = 65536;
    reg        qw  [0:QN-1];
    reg [21:0] qa  [0:QN-1];
    reg [7:0]  qd  [0:QN-1];
    reg [15:0] res [0:QN-1];
    integer    lat [0:QN-1];
    integer    tdone [0:QN-1];
    integer head = 0, tail = 0, n_done = 0, n_spur = 0, cyc = 0, t0 = 0, gcnt = 0;
    integer gap_extra = 0;                  // pausa extra entre operaciones (ciclos)
    integer abort_after = -1;               // (f): baja req a los N ciclos de pedir (una vez)
    integer abort_gap = 0;                  //      y vuelve a pedir tras estos ciclos
    integer n_abort = 0;
    reg     busy = 1'b0;

    always @(posedge clk) cyc <= cyc + 1;
    always @(posedge clk) begin
        if (busy) begin
            if (!done && abort_after >= 0 && cyc - t0 == abort_after) begin
                // operacion abortada (como un reset del cliente): se descarta
                req <= 1'b0;
                res[head] <= 16'hDEAD;
                head  <= head + 1;
                busy  <= 1'b0;
                gcnt  <= abort_gap;
                abort_after <= -1;
                n_abort <= n_abort + 1;
            end
            else if (done) begin
                req <= 1'b0;
                res[head]   <= dout;
                lat[head]   <= cyc - t0;
                tdone[head] <= cyc;
                head   <= head + 1;
                busy   <= 1'b0;
                gcnt   <= GAP + gap_extra;
                n_done <= n_done + 1;
            end
        end
        else begin
            if (done) begin
                n_spur <= n_spur + 1;
                $display("  [ERR cliente %m %0t] done sin operacion en curso", $time);
            end
            if (gcnt > 0) gcnt <= gcnt - 1;
            else if (head != tail) begin
                req <= 1'b1; we <= qw[head]; addr <= qa[head]; wdata <= qd[head];
                busy <= 1'b1; t0 <= cyc;
            end
        end
    end
    task push(input w, input [21:0] a, input [7:0] d);
        begin qw[tail] = w; qa[tail] = a; qd[tail] = d; tail = tail + 1; end
    endtask
endmodule

// ----------------------------------------------------------------------------
module tb_wv_to_sdram;
    localparam real T = 9.259;              // 108 MHz
    localparam integer REFRESH_CYCLES = 780;
    localparam integer WDOG = 4096;

    reg clk = 1'b0, rst_n = 1'b0;
    always #(T / 2.0) clk = ~clk;

    wire        c1_req, c1_we, c2_req, c2_we;
    wire [21:0] c1_addr, c2_addr;
    wire [7:0]  c1_wdata, c2_wdata;
    wire [15:0] wv_dout;
    wire        wv_done, wv2_done, sd_timeout;
    wire [22:2] bus_address;
    wire        bus_valid, bus_write, bus_refresh, bus_rdata_en, bus_ready;
    wire [31:0] bus_wdata, bus_rdata;
    wire [3:0]  bus_wdata_mask;

`ifdef NEG_HEAD
    assign wv2_done = 1'b0;
    wv_to_sdram #(.REFRESH_CYCLES(REFRESH_CYCLES)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .wv_req(c1_req), .wv_we(c1_we), .wv_addr(c1_addr), .wv_wdata(c1_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done), .sd_timeout(sd_timeout),
        .bus_address(bus_address), .bus_valid(bus_valid), .bus_write(bus_write),
        .bus_refresh(bus_refresh), .bus_wdata(bus_wdata), .bus_wdata_mask(bus_wdata_mask),
        .bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en), .bus_ready(bus_ready)
    );
    localparam integer TWO = 0;
`else
    wv_to_sdram #(.REFRESH_CYCLES(REFRESH_CYCLES)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .wv_req(c1_req), .wv_we(c1_we), .wv_addr(c1_addr), .wv_wdata(c1_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done), .sd_timeout(sd_timeout),
        .wv2_req(c2_req), .wv2_we(c2_we), .wv2_addr(c2_addr), .wv2_wdata(c2_wdata),
        .wv2_done(wv2_done),
        .bus_address(bus_address), .bus_valid(bus_valid), .bus_write(bus_write),
        .bus_refresh(bus_refresh), .bus_wdata(bus_wdata), .bus_wdata_mask(bus_wdata_mask),
        .bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en), .bus_ready(bus_ready)
    );
    localparam integer TWO = 1;
`endif

    fake_sdram_ctrl ctrl (
        .clk(clk), .rst_n(rst_n),
        .bus_address(bus_address), .bus_valid(bus_valid), .bus_write(bus_write),
        .bus_refresh(bus_refresh), .bus_wdata(bus_wdata), .bus_wdata_mask(bus_wdata_mask),
        .bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en), .bus_ready(bus_ready)
    );

    wv_client c1 (.clk(clk), .rst_n(rst_n), .req(c1_req), .we(c1_we), .addr(c1_addr),
                  .wdata(c1_wdata), .dout(wv_dout), .done(wv_done));
    wv_client c2 (.clk(clk), .rst_n(rst_n), .req(c2_req), .we(c2_we), .addr(c2_addr),
                  .wdata(c2_wdata), .dout(wv_dout), .done(wv2_done));

    // ------------------------------------------------------------------
    //  Marcador
    // ------------------------------------------------------------------
    integer errors = 0, checks = 0;
    task ok(input cond, input [1599:0] what);
        begin
            checks = checks + 1;
            if (cond !== 1'b1) begin errors = errors + 1; $display("  [FAIL] %0s", what); end
            else $display("  [ok]   %0s", what);
        end
    endtask
    task fin;
        begin
            $display("== %0d comprobaciones, %0d errores ==", checks, errors);
            if (errors == 0) $display("RESULTADO: PASS"); else $display("RESULTADO: FAIL");
            $finish;
        end
    endtask

    integer n_fire = 0;
    always @(posedge clk) if (u_dut.wdog_fire) n_fire = n_fire + 1;

    // ------------------------------------------------------------------
    //  Contenido: cada cliente ve su propio espacio de 4 MB. El banco usa 32
    //  regiones de 4 KB repartidas por los 4 MB (el principio y el final de
    //  cada bloque de 256 KB: a[17:12] = 00h o 3Fh) y una copia en sombra por
    //  cliente, indexada por {a[21:18], a[17], a[11:0]}.
    // ------------------------------------------------------------------
    reg [7:0] sh1 [0:131071];
    reg [7:0] sh2 [0:131071];
    function [16:0] sidx(input [21:0] a); sidx = {a[21:18], a[17], a[11:0]}; endfunction
    function [21:0] raddr(input [16:0] s); raddr = {s[16:13], {6{s[12]}}, s[11:0]}; endfunction
    function [7:0] init_byte(input integer c, input [21:0] a);
        init_byte = a[7:0] ^ a[15:8] ^ {2'b00, a[21:16]} ^ (c == 2 ? 8'hC3 : 8'h3C);
    endfunction

    // espera a que el cliente haya completado n operaciones (o timeout)
    task wait_ops(input integer c, input integer n, input integer max_cyc, output reg done_ok);
        integer w;
        begin
            w = 0; done_ok = 1'b0;
            while (w < max_cyc && !done_ok) begin
                @(posedge clk); #1;
                if ((c == 1 ? c1.head : c2.head) >= n) done_ok = 1'b1;
                w = w + 1;
            end
        end
    endtask

    // operacion con su valor esperado (la sombra se actualiza al encolar:
    // cada cliente hace sus operaciones en orden)
    reg [15:0] exp1 [0:65535];
    reg [15:0] exp2 [0:65535];
    task op(input integer c, input w, input [21:0] a, input [7:0] d);
        reg [16:0] s0, s1;
        begin
            s0 = sidx({a[21:1], 1'b0}); s1 = sidx({a[21:1], 1'b1});
            if (c == 1) begin
                if (w) sh1[sidx(a)] = d;
                exp1[c1.tail] = {sh1[s1], sh1[s0]};
                c1.push(w, a, d);
            end
            else begin
                if (w) sh2[sidx(a)] = d;
                exp2[c2.tail] = {sh2[s1], sh2[s0]};
                c2.push(w, a, d);
            end
        end
    endtask
    // operacion que se va a quedar atascada: no toca la sombra
    task op_stuck(input integer c, input w, input [21:0] a, input [7:0] d);
        begin
            if (c == 1) begin exp1[c1.tail] = 16'hFFFF; c1.push(w, a, d); end
            else        begin exp2[c2.tail] = 16'hFFFF; c2.push(w, a, d); end
        end
    endtask
    // operacion que el cliente va a abortar: ni toca la sombra ni se espera dato
    task op_abort(input integer c, input w, input [21:0] a, input [7:0] d);
        begin
            if (c == 1) begin exp1[c1.tail] = 16'hDEAD; c1.push(w, a, d); end
            else        begin exp2[c2.tail] = 16'hDEAD; c2.push(w, a, d); end
        end
    endtask
    // (f) un caso de operacion abortada del cliente c:
    //   kind 0 lectura / 1 escritura; mode 3 = lenta (se aborta en RD/WR),
    //   1 = ignorada (ACCEPT colgado: se aborta y salta el watchdog)
    task abort_case(input integer c, input integer kind, input integer mode, input [21:0] na, input [1199:0] name);
        integer h0, f0, sp0, ab0, wmax;
        reg     d_ok;
        begin
            f0 = n_fire;
            sp0 = c1.n_spur + c2.n_spur;
            ab0 = (c == 1) ? c1.n_abort : c2.n_abort;
            ctrl.inj_kind = kind; ctrl.inj_mode = mode;
            ctrl.inj_cycles = 80;
            if (c == 1) begin c1.abort_after = (mode == 1) ? 200 : 25; c1.abort_gap = 0; end
            else        begin c2.abort_after = (mode == 1) ? 200 : 25; c2.abort_gap = 0; end
            h0 = (c == 1) ? c1.tail : c2.tail;
            // la abortada, en la region 2C0000h (contenido distinto del de la nueva)
            op_abort(c, kind == 1, 22'h2C_0F31, 8'hE7);
            // y en cuanto suelta, una lectura nueva de OTRA direccion
            op(c, 1'b0, na, 8'h00);
            wmax = (mode == 1) ? 3 * WDOG : 2000;
            wait_ops(c, h0 + 2, wmax, d_ok);
            ok(d_ok && ((c == 1) ? c1.n_abort : c2.n_abort) == ab0 + 1,
               {name, ": el cliente aborta y su peticion nueva termina"});
            ok(n_bad(c, h0 + 1, h0 + 2) == 0,
               {name, ": la peticion nueva recibe SU dato (no el de la abortada)"});
            repeat (300) @(posedge clk); #1;
            ok(c1.n_spur + c2.n_spur == sp0, {name, ": ningun done de mas (el de la abortada no se entrega)"});
            if (mode == 1) ok(n_fire == f0 + 1, {name, ": el watchdog salta una vez"});
            else           ok(n_fire == f0,     {name, ": sin watchdog"});
            ctrl.inj_mode = 0;
        end
    endtask
    function integer n_bad(input integer c, input integer from, input integer to);
        integer j;
        begin
            n_bad = 0;
            for (j = from; j < to; j = j + 1)
                if (c == 1 ? (!c1.qw[j] && c1.res[j] !== exp1[j]) : (!c2.qw[j] && c2.res[j] !== exp2[j])) begin
                    n_bad = n_bad + 1;
                    if (n_bad <= 4)
                        $display("         cliente %0d op %0d (%s %06x): %04x, esperado %04x", c, j,
                                 (c == 1 ? c1.qw[j] : c2.qw[j]) ? "WR" : "RD",
                                 c == 1 ? c1.qa[j] : c2.qa[j],
                                 c == 1 ? c1.res[j] : c2.res[j], c == 1 ? exp1[j] : exp2[j]);
                end
        end
    endfunction

    // un caso de watchdog en una lectura / escritura de un cliente
    //   kind: 0 lectura, 1 escritura; mode: 1 = ACCEPT (ignorada), 2 = colgada en RD/WR
    task wdog_case(input integer owner, input integer kind, input integer mode, input [1199:0] name);
        integer other, o_head0, x_done0, f0, x_head0, k_stuck;
        reg     d_ok, x_ok;
        reg [21:0] a;
        begin
            other = (owner == 1) ? 2 : 1;
            f0 = n_fire;
            // el controlador se atasca con la siguiente orden de ese tipo
            ctrl.inj_kind = kind; ctrl.inj_mode = mode; ctrl.inj_cycles = WDOG + 1500;
            a = 22'h2C_0105 + owner;            // region 2C0000h
            k_stuck = (owner == 1) ? c1.tail : c2.tail;
            op_stuck(owner, kind == 1, a, 8'h77);
            // ...y mientras, el otro cliente pide una lectura (solo con dos clientes)
            x_head0 = (other == 1) ? c1.tail : c2.tail;
            x_done0 = (other == 1) ? c1.n_done : c2.n_done;
            repeat (200) @(posedge clk); #1;
            if (TWO) op(other, 1'b0, 22'h18_0222, 8'h00);
            wait_ops(owner, k_stuck + 1, 3 * WDOG, d_ok);
            ok(d_ok, {name, ": el propietario recibe su done tras el watchdog"});
            ok(n_fire == f0 + 1, {name, ": el watchdog salta una vez"});
            if (kind == 0)
                ok((owner == 1 ? c1.res[k_stuck] : c2.res[k_stuck]) === 16'hFFFF,
                   {name, ": el propietario recibe el dato envenenado FFFFh"});
            if (TWO) begin
                // en el instante del done del dueño, el otro no habia recibido nada
                ok(((other == 1) ? c1.n_done : c2.n_done) == x_done0 &&
                   ((other == 1) ? c1.n_spur : c2.n_spur) == 0,
                   {name, ": el otro cliente no recibe ningun done de mas"});
                wait_ops(other, x_head0 + 1, 2 * WDOG, x_ok);
                ok(x_ok && n_bad(other, x_head0, x_head0 + 1) == 0,
                   {name, ": la lectura del otro cliente se sirve despues, con su dato bueno"});
            end
            // el dueño sigue funcionando
            op(owner, 1'b1, 22'h00_0040 + owner, 8'h5A + owner[7:0]);
            op(owner, 1'b0, 22'h00_0040 + owner, 8'h00);
            wait_ops(owner, k_stuck + 3, 2 * WDOG, d_ok);
            ok(d_ok && n_bad(owner, k_stuck + 1, k_stuck + 3) == 0,
               {name, ": y el propietario sigue funcionando (escribe y relee)"});
            repeat (ctrl.inj_cycles + 100) @(posedge clk);     // que el controlador vuelva
        end
    endtask

    // ------------------------------------------------------------------
    integer i, j, k, n0, n1, n2, m, lmax, lsum, h1, h2, f0, t_end1, t_last2;
    integer ref_gap_max, last_ref;
    reg     okw;
    reg [21:0] a;
    reg [31:0] r;

    initial begin
        // contenido inicial por la puerta de atras, en el mapeo que se espera
        // (lo que va por la de delante se comprueba aparte en (d))
        for (i = 0; i < 131072; i = i + 1) begin
            a = raddr(i[16:0]);
            sh1[i] = init_byte(1, a);
            sh2[i] = init_byte(2, a);
        end
        for (i = 0; i < 131072; i = i + 4) begin
            a = raddr(i[16:0]);
            ctrl.mem[{1'b0, a[21:2]}] = {sh1[i+3], sh1[i+2], sh1[i+1], sh1[i]};
            ctrl.mem[{1'b1, a[21:2]}] = {sh2[i+3], sh2[i+2], sh2[i+1], sh2[i]};
        end

        repeat (5) @(posedge clk); #1 rst_n = 1'b1;
        wait (bus_ready === 1'b1);
        repeat (10) @(posedge clk); #1;

        // ==============================================================
        $display("== (g) init del controlador de %0d ciclos con el puente en reposo ==", ctrl.init_cyc);
        wait (ctrl.n_ref >= 2); repeat (10) @(posedge clk); #1;
        ok(n_fire == 0 && sd_timeout === 1'b0,
           "(g) el watchdog no ha contado durante el init: no salta en el primer refresco");

        // ==============================================================
        $display("== (d) mapeo: cliente 1 -> bancos 0-1, cliente 2 -> bancos 2-3 ==");
        n0 = ctrl.n_log;
        op(1, 1'b1, 22'h00_0235, 8'hA1);
        wait_ops(1, 1, 1000, okw);
        m = ctrl.n_log - 1; while (m > n0 && ctrl.log_kind[m] == 2) m = m - 1;
        ok(okw && ctrl.log_addr[m] === {1'b0, 20'h0008D}, "cliente 1, escritura en 000235h: orden a la palabra 0008Dh del banco 0");
        r = ctrl.mem[{1'b0, 20'h0008D}];
        ok(r[15:8] === 8'hA1 && r[7:0] === sh1[16'h0234] && r[31:16] === {sh1[16'h0237], sh1[16'h0236]},
           "  y solo cambia la lane 1 (las otras tres intactas)");
        if (TWO) begin
            n0 = ctrl.n_log;
            op(2, 1'b1, 22'h00_0235, 8'hB2);
            wait_ops(2, 1, 1000, okw);
            m = ctrl.n_log - 1; while (m > n0 && ctrl.log_kind[m] == 2) m = m - 1;
            ok(okw && ctrl.log_addr[m] === {1'b1, 20'h0008D}, "cliente 2, misma direccion: orden con bus_address[22] = 1 (banco 2)");
            r = ctrl.mem[{1'b1, 20'h0008D}];
            ok(r[15:8] === 8'hB2 && ctrl.mem[{1'b0, 20'h0008D}][15:8] === 8'hA1,
               "  sin alias: el byte del cliente 1 en el banco 0 sigue siendo A1h");
            // cerca del final de los 256 KB del ADPCM y del final de los 4 MB
            op(2, 1'b1, 22'h03_FFFF, 8'hC4);
            op(2, 1'b1, 22'h3F_FFFE, 8'hD5);
            wait_ops(2, 3, 1000, okw);
            ok(okw && ctrl.mem[{1'b1, 20'h0FFFF}][31:24] === 8'hC4, "cliente 2, 03FFFFh (fin de 256 KB): palabra 0FFFFh del banco 2, lane 3");
            ok(ctrl.mem[{1'b1, 20'hFFFFF}][23:16] === 8'hD5, "cliente 2, 3FFFFEh: ultima palabra del banco 3, lane 2");
            op(2, 1'b0, 22'h00_0234, 8'h00);
            op(2, 1'b0, 22'h03_FFFE, 8'h00);
            op(2, 1'b0, 22'h3F_FFFC, 8'h00);
            op(2, 1'b0, 22'h3F_FFFE, 8'h00);
            wait_ops(2, 7, 2000, okw);
            ok(okw && n_bad(2, 3, 7) == 0, "cliente 2: relee lo suyo (media palabra correcta en las dos mitades)");
        end
        op(1, 1'b1, 22'h3F_FFFE, 8'hE6);
        op(1, 1'b0, 22'h00_0234, 8'h00);
        op(1, 1'b0, 22'h3F_FFFE, 8'h00);
        wait_ops(1, 4, 2000, okw);
        ok(okw && ctrl.mem[{1'b0, 20'hFFFFF}][23:16] === 8'hE6 && n_bad(1, 1, 4) == 0,
           "cliente 1: 3FFFFEh va a la ultima palabra del banco 1 y relee lo suyo, no lo del cliente 2");

        // ==============================================================
        if (TWO) begin
            $display("== (c) prioridades y hambre del cliente 2 ==");
            // las dos peticiones en el mismo flanco: gana wv
            wait (u_dut.ref_cnt == 16'd100); @(posedge clk); #1;
            n0 = ctrl.n_log;
            op(1, 1'b0, 22'h00_0010, 8'h00);
            op(2, 1'b0, 22'h00_0010, 8'h00);
            wait_ops(1, c1.tail, 1000, okw); wait_ops(2, c2.tail, 1000, okw);
            ok(ctrl.n_log - n0 == 2 && ctrl.log_addr[n0][22] === 1'b0 && ctrl.log_addr[n0+1][22] === 1'b1,
               "peticion de los dos a la vez: primero el cliente 1 (wv), luego el 2");
            // refresco pendiente con las dos esperando: primero el refresco
            ctrl.inj_kind = 0; ctrl.inj_mode = 3; ctrl.inj_cycles = REFRESH_CYCLES + 300;
            n0 = ctrl.n_log;
            op(1, 1'b0, 22'h00_0020, 8'h00);            // lectura lenta: deja vencer el refresco
            repeat (100) @(posedge clk); #1;
            op(1, 1'b0, 22'h00_0024, 8'h00);
            op(2, 1'b0, 22'h00_0024, 8'h00);
            wait_ops(1, c1.tail, 3000, okw); wait_ops(2, c2.tail, 3000, okw);
            ok(ctrl.n_log - n0 == 4 && ctrl.log_kind[n0+1] == 2 && ctrl.log_addr[n0+2][22] === 1'b0 &&
               ctrl.log_addr[n0+3][22] === 1'b1,
               "refresco vencido con los dos clientes esperando: refresco, cliente 1, cliente 2");
            ok(n_bad(1, 0, c1.tail) == 0 && n_bad(2, 0, c2.tail) == 0, "  y todos los datos bien");

            // hambre: cliente 1 saturado al ritmo maximo de wave_sdram (GAP = 1),
            // cliente 2 al ritmo de un OTIR a 3,58 MHz (una cada ~5,9 us = 640 ciclos)
            // y despues sin pausa
            h1 = c1.tail; h2 = c2.tail;
            for (i = 0; i < 6000; i = i + 1) begin
                a = raddr($random); op(1, i[0], a, $random);
            end
            for (i = 0; i < 40; i = i + 1) begin
                a = raddr($random); op(2, i[0], a, $random);
                c2.gap_extra = 640;
            end
            wait_ops(2, c2.tail, 200000, okw);
            t_last2 = c2.tdone[c2.tail - 1];
            c2.gap_extra = 0;
            for (i = 0; i < 300; i = i + 1) begin
                a = raddr($random); op(2, i[0], a, $random);
            end
            wait_ops(2, c2.tail, 200000, okw);
            t_last2 = c2.tdone[c2.tail - 1];
            wait_ops(1, c1.tail, 400000, okw);
            t_end1 = c1.tdone[c1.tail - 1];
            lmax = 0; lsum = 0;
            for (i = h2; i < c2.tail; i = i + 1) begin
                if (c2.lat[i] > lmax) lmax = c2.lat[i];
                lsum = lsum + c2.lat[i];
            end
            $display("         cliente 2: %0d operaciones con el cliente 1 saturado; latencia media %0d ciclos, maxima %0d (%0.0f ns)",
                     c2.tail - h2, lsum / (c2.tail - h2), lmax, lmax * T);
            ok(t_last2 < t_end1, "el cliente 2 termina TODAS sus operaciones mientras el 1 sigue saturado (no muere de hambre)");
            ok(lmax < 60, "  con una latencia maxima de una operacion del cliente 1 + un refresco + la suya");
            lmax = 0;
            for (i = h1; i < c1.tail; i = i + 1) if (c1.lat[i] > lmax) lmax = c1.lat[i];
            $display("         cliente 1: latencia maxima %0d ciclos (%0.0f ns)", lmax, lmax * T);
            ok(n_bad(1, h1, c1.tail) == 0 && n_bad(2, h2, c2.tail) == 0, "  datos bien en los dos clientes");
        end

        // ==============================================================
        $display("== (b) watchdog en ACCEPT, RD y WR: el done es del propietario ==");
        wdog_case(1, 0, 1, "cliente 1, lectura ignorada (ACCEPT)");
        wdog_case(1, 1, 1, "cliente 1, escritura ignorada (ACCEPT)");
        wdog_case(1, 0, 2, "cliente 1, lectura colgada (RD)");
        wdog_case(1, 1, 2, "cliente 1, escritura colgada (WR)");
        if (TWO) begin
            wdog_case(2, 0, 1, "cliente 2, lectura ignorada (ACCEPT)");
            wdog_case(2, 1, 1, "cliente 2, escritura ignorada (ACCEPT)");
            wdog_case(2, 0, 2, "cliente 2, lectura colgada (RD)");
            wdog_case(2, 1, 2, "cliente 2, escritura colgada (WR)");
        end
        ok(sd_timeout === 1'b1, "sd_timeout queda a 1 (pegajoso, al LED)");

        // ==============================================================
        $display("== (a) watchdog durante un REFRESCO con peticiones pendientes ==");
        // (a1) el controlador acepta el refresco y se cuelga con ready = 0 mas
        //      de lo que tarda el watchdog; luego vuelve
        f0 = n_fire;
        ctrl.inj_kind = 2; ctrl.inj_mode = 2; ctrl.inj_cycles = WDOG + 2000;
        wait (ctrl.st == 3); repeat (100) @(posedge clk); #1;
        h1 = c1.tail; h2 = c2.tail;
        op(1, 1'b0, 22'h00_0234, 8'h00);
        if (TWO) op(2, 1'b0, 22'h00_0234, 8'h00);
        wait_ops(1, h1 + 1, 4 * WDOG, okw);
        ok(okw, "(a1) refresco colgado: la lectura del cliente 1 se sirve al volver el controlador");
        ok(n_bad(1, h1, h1 + 1) == 0, "(a1)   con su dato bueno (no envenenado)");
        if (TWO) begin
            wait_ops(2, h2 + 1, 4 * WDOG, okw);
            ok(okw && n_bad(2, h2, h2 + 1) == 0, "(a1)   y la del cliente 2 tambien");
        end
        ok(n_fire == f0 + 1, "(a1)   el watchdog salto una vez");
        // (a2) el controlador ignora el refresco (ACCEPT con ready = 1)
        repeat (2000) @(posedge clk); #1;
        f0 = n_fire;
        ctrl.inj_kind = 2; ctrl.inj_mode = 1;
        i = 0;
        while (ctrl.inj_mode != 0 && i < 4 * REFRESH_CYCLES) begin @(posedge clk); i = i + 1; end
        ok(ctrl.inj_mode == 0, "(a2) el puente sigue emitiendo refrescos");
        repeat (100) @(posedge clk); #1;
        h1 = c1.tail; h2 = c2.tail;
        op(1, 1'b0, 22'h3F_FFFE, 8'h00);
        if (TWO) op(2, 1'b0, 22'h03_FFFE, 8'h00);
        wait_ops(1, h1 + 1, 4 * WDOG, okw);
        ok(okw && n_bad(1, h1, h1 + 1) == 0, "(a2) refresco ignorado: la lectura del cliente 1 se sirve, con su dato");
        if (TWO) begin
            wait_ops(2, h2 + 1, 4 * WDOG, okw);
            ok(okw && n_bad(2, h2, h2 + 1) == 0, "(a2)   y la del cliente 2 tambien");
        end
        ok(n_fire == f0 + 1, "(a2)   el watchdog salto una vez");
        ok(c1.n_spur == 0 && c2.n_spur == 0, "ningun cliente recibio un done sin operacion en curso");

`ifdef NEG_HEAD
        fin;
`endif
        // ==============================================================
        $display("== (f) operacion abortada por el cliente (reset del cliente a mitad) ==");
        repeat (2000) @(posedge clk); #1;
        abort_case(2, 0, 3, 22'h18_0A52, "cliente 2, lectura abortada en RD");
        abort_case(2, 1, 3, 22'h18_0A56, "cliente 2, escritura abortada en WR");
        abort_case(2, 0, 1, 22'h18_0A5A, "cliente 2, lectura abortada en ACCEPT colgado");
        abort_case(1, 0, 3, 22'h18_0A5E, "cliente 1, lectura abortada en RD");
        abort_case(1, 1, 1, 22'h18_0A62, "cliente 1, escritura abortada en ACCEPT colgado");

        // ==============================================================
        $display("== (e) trafico aleatorio de los dos clientes con el refresco en marcha ==");
        repeat (3000) @(posedge clk); #1;
        f0 = n_fire; n0 = ctrl.n_err;
        h1 = c1.tail; h2 = c2.tail; n1 = ctrl.n_log;
        for (i = 0; i < 4000; i = i + 1) begin
            a = raddr($random); op(1, ($random & 3) == 0, a, $random);
            a = raddr($random); op(2, ($random & 1) == 0, a, $random);
        end
        c1.gap_extra = 3; c2.gap_extra = 7;
        wait_ops(1, c1.tail, 400000, okw);
        wait_ops(2, c2.tail, 400000, okw);
        ok(okw && n_bad(1, h1, c1.tail) == 0 && n_bad(2, h2, c2.tail) == 0,
           "4000 + 4000 operaciones aleatorias: todas las lecturas devuelven lo esperado");
        ref_gap_max = 0; last_ref = -1;
        for (i = n1; i < ctrl.n_log; i = i + 1)
            if (ctrl.log_kind[i] == 2) begin
                if (last_ref >= 0 && ctrl.log_cyc[i] - last_ref > ref_gap_max) ref_gap_max = ctrl.log_cyc[i] - last_ref;
                last_ref = ctrl.log_cyc[i];
            end
        $display("         refrescos: separacion maxima %0d ciclos (%0.2f us; programada %0d)", ref_gap_max, ref_gap_max * T / 1000.0, REFRESH_CYCLES + 1);
        ok(ref_gap_max > 0 && ref_gap_max < REFRESH_CYCLES + 40, "el refresco sigue a su ritmo con trafico de los dos");
        ok(n_fire == f0, "el watchdog no salta con trafico normal");

        $display("== final ==");
        ok(ctrl.n_err == 0, "el controlador no vio ninguna orden ilegal (con ready = 0 o valid + refresh)");
        ok(c1.n_spur == 0 && c2.n_spur == 0, "ningun done sin operacion en curso");
        $display("         ordenes: %0d RD, %0d WR, %0d REF, %0d ignoradas; %0d disparos del watchdog en total",
                 ctrl.n_rd, ctrl.n_wr, ctrl.n_ref, ctrl.n_ign, n_fire);
        fin;
    end

    initial begin
        #200_000_000;
        $display("  [FAIL] timeout global");
        errors = errors + 1;
        fin;
    end
endmodule

`default_nettype wire

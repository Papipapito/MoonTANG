// ============================================================================
// tb_smd.v — MoonTANG ENTERO sobre un modelo del cartucho MSXhdmi_tn20k_smd.
//
// Que se simula: el top real de la variante SMD (convertido con sv2v), con los
// rPLL, CLKDIV, BUFG y serializadores de la libreria de simulacion de Gowin,
// conectado POR NUMERO DE PIN (envoltorio generado del .cst) a un modelo de la
// placa cuyos pines salen de la PCB real de KiCad; la flash SPI con una YRW801
// sintetica; la SDRAM embebida; un Z80 a 3,58 MHz con su temporizacion real; y
// un receptor HDMI independiente colgado de los simbolos TMDS.
//
// OJO: en esta placa /WAIT no esta cableado, asi que el Z80 del banco NO espera
// nunca. Las lecturas de la memoria de ondas se prueban tal como las veria un
// MSX de verdad con este cartucho.
//
// Lo que NO puede demostrar: la electronica (niveles, el televisor) ni el oido.
// ============================================================================
`timescale 1ns/1ps

module tb_smd;
    parameter integer QUIET      = 0;
    parameter integer STOP_AFTER = 99;      // corta tras la fase N (4 = D)
    parameter integer FRAMES     = 1;       // cuadros de video que se vuelcan a disco
    parameter integer MIRROR     = 1;       // 0 = sin el espejo de lectura (control negativo)

    localparam real TH = 139.6825;          // medio periodo de 3,579545 MHz

    // ------------------------------------------------------------------
    //  El MSX
    // ------------------------------------------------------------------
    reg        msx_on = 1'b0;
    reg        clk358 = 1'b0;
    always #(TH) if (msx_on) clk358 = ~clk358; else clk358 = 1'b0;

    reg [15:0] a       = 16'h0000;
    reg [7:0]  d_out   = 8'h00;
    reg        d_oe    = 1'b0;
    reg        mreq_n  = 1'b0, iorq_n = 1'b0, rd_n = 1'b0, wr_n = 1'b0;
    reg        reset_n = 1'b0, m1_n = 1'b0, rfsh_n = 1'b0;
    reg        sltsl_n = 1'b0;
    tri1 [7:0] s_d;
    assign     s_d = d_oe ? d_out : 8'hzz;

    // ------------------------------------------------------------------
    //  La placa y la FPGA
    // ------------------------------------------------------------------
    wire [88:1] pin;
    wire        sd_clk, sd_cke, sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n;
    wire [31:0] sd_dq;
    wire [10:0] sd_a;
    wire [1:0]  sd_ba;
    wire [3:0]  sd_dqm;

    GSR GSR (.GSRI(1'b1));

    moontang_smd_pins fpga (
        .pin(pin),
        .O_sdram_clk(sd_clk), .O_sdram_cke(sd_cke), .O_sdram_cs_n(sd_cs_n),
        .O_sdram_ras_n(sd_ras_n), .O_sdram_cas_n(sd_cas_n), .O_sdram_wen_n(sd_we_n),
        .IO_sdram_dq(sd_dq), .O_sdram_addr(sd_a), .O_sdram_ba(sd_ba), .O_sdram_dqm(sd_dqm)
    );
    // 4 KB de "YRW801" bastan para la prueba (la carga entera son 2 MB de SPI)
    defparam fpga.u_top.u_core.u_loader.WAVE_SIZE = 23'h001000;
    // ...y la espera de arranque de la flash (185 ms en la placa) se acorta
    defparam fpga.u_top.u_core.u_flash.STARTUP_WAIT = 32'd2000;
    // ...y la suma esperada es la de esos 4 KB sinteticos
    defparam fpga.u_top.u_core.u_loader.EXPECTED_SUM = 32'h0007FFAD;
    defparam fpga.u_top.u_core.WAVE_RD_MIRROR = MIRROR;

    sdram_model sdram (
        .clk(sd_clk), .cke(sd_cke), .cs_n(sd_cs_n), .ras_n(sd_ras_n), .cas_n(sd_cas_n),
        .we_n(sd_we_n), .addr(sd_a), .ba(sd_ba), .dqm(sd_dqm), .dq(sd_dq)
    );

    wire cart_drives_d, j2_1, j2_8;
    smd_board board (
        .pin(pin),
        .s_a(a), .s_d(s_d),
        .s_mreq_n(mreq_n), .s_iorq_n(iorq_n), .s_rd_n(rd_n), .s_wr_n(wr_n),
        .s_reset_n(reset_n), .s_sltsl_n(sltsl_n), .s_clock(clk358),
        .cart_drives_d(cart_drives_d), .j2_1(j2_1), .j2_8(j2_8)
    );

    // ------------------------------------------------------------------
    //  Marcador
    // ------------------------------------------------------------------
    integer errors = 0, checks = 0;
    task fin;
        begin
            $display("== %0d comprobaciones, %0d errores ==", checks, errors);
            if (errors == 0) $display("RESULTADO: PASS");
            else             $display("RESULTADO: FAIL");
            $finish;
        end
    endtask
    task ok(input cond, input [799:0] what);
        begin
            checks = checks + 1;
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("  [FAIL] %0s", what);
            end
            else if (!QUIET) $display("  [ok]   %0s", what);
        end
    endtask

    // ------------------------------------------------------------------
    //  Vigilantes del bus de datos
    // ------------------------------------------------------------------
    //  1) U3 solo puede mirar hacia el MSX durante una lectura de E/S nuestra.
    wire [7:0] port = a[7:0];
    wire ours = (port[7:2] == 6'b110001) || (port[7:1] == 7'b0111111);
    wire legit_rd = msx_on && reset_n && !iorq_n && !rd_n && ours;
    integer bad_drive = 0;
    reg     drive_seen = 1'b0;
    always @(posedge cart_drives_d) begin
        drive_seen = 1'b1;
        if (!legit_rd) begin
            bad_drive = bad_drive + 1;
            $display("  [FAIL %0t] la placa conduce D0-D7 sin que le lean: A=%04x iorq=%b rd=%b wr=%b mreq=%b on=%b",
                     $time, a, iorq_n, rd_n, wr_n, mreq_n, msx_on);
        end
    end
    //  2) INVARIANTE de U3 (su /OE esta a masa): la FPGA solo puede conducir sus
    //     pines de datos mientras DATADIR esta a 0, y con el giro ya hecho.
    integer bad_oe = 0;
    realtime t_dir_low = 0;
    wire fpga_oe  = fpga.u_top.u_bus.oe & fpga.u_top.u_bus.turn;
    wire datadir  = pin[18];
    always @(negedge datadir) t_dir_low = $realtime;
    always @(posedge fpga_oe)
        if (datadir !== 1'b0 || ($realtime - t_dir_low) < 10.0) begin
            bad_oe = bad_oe + 1;
            $display("  [FAIL %0t] la FPGA conduce datos con U3 aun mirando hacia ella", $time);
        end
    always @(posedge datadir) #1 if (fpga_oe) begin
        bad_oe = bad_oe + 1;
        $display("  [FAIL %0t] DATADIR vuelve a 1 con la FPGA aun conduciendo", $time);
    end
    //  3) cuanto tarda en soltar el bus tras subir /RD
    realtime t_rd_up = 0;
    real     rel_max = 0;
    always @(posedge rd_n) t_rd_up = $realtime;
    always @(negedge cart_drives_d) if (msx_on && ($realtime - t_rd_up) > rel_max) rel_max = $realtime - t_rd_up;

    // ------------------------------------------------------------------
    //  Ciclos de bus del Z80 (3,58 MHz, tiempos del Z80A). Sin /WAIT.
    // ------------------------------------------------------------------
    integer  setup_viol = 0;
    realtime t_iorq, t_drv;
    real     drv_lat_max = 0;
    always @(posedge cart_drives_d) begin
        t_drv = $realtime;
        if (msx_on && (t_drv - t_iorq) > drv_lat_max) drv_lat_max = t_drv - t_iorq;
    end

    task m1_fetch(input [15:0] pc, input [7:0] opcode);
        begin
            @(posedge clk358); #100 a = pc; m1_n = 1'b0;
            @(negedge clk358); #80 mreq_n = 1'b0; rd_n = 1'b0;
            @(posedge clk358); #60 d_out = opcode; d_oe = 1'b1;      // la ROM del MSX
            @(posedge clk358); #90 mreq_n = 1'b1; rd_n = 1'b1; m1_n = 1'b1;
            #20 d_oe = 1'b0; a = {8'h12, 8'h7F}; rfsh_n = 1'b0;      // refresco: I=12h, R=7Fh
            @(negedge clk358); #80 mreq_n = 1'b0;
            @(posedge clk358);
            @(negedge clk358); #80 mreq_n = 1'b1;
            @(posedge clk358); #80 rfsh_n = 1'b1;
        end
    endtask

    task io_wr(input [15:0] p, input [7:0] v);
        begin
            m1_fetch(16'h4000, 8'hD3);              // OUT (n),A
            @(posedge clk358); #110 a = p;
            @(negedge clk358); #100 d_out = v; d_oe = 1'b1;
            @(posedge clk358); #75 iorq_n = 1'b0; #5 wr_n = 1'b0; t_iorq = $realtime;
            @(posedge clk358);                      // TW* automatico
            @(posedge clk358);                      // T3
            @(negedge clk358); #80 wr_n = 1'b1; iorq_n = 1'b1;
            #60 d_oe = 1'b0;
        end
    endtask

    reg [7:0] rdv, rd_early;
    reg       rd_driven;
    task io_rd_raw(input [15:0] p);               // solo el ciclo de E/S
        begin
            @(posedge clk358); #110 a = p;
            @(posedge clk358); #75 iorq_n = 1'b0; #10 rd_n = 1'b0; t_iorq = $realtime;
            @(posedge clk358);                      // TW* automatico
            @(posedge clk358);                      // T3
            #(TH - 50.0) rd_early = s_d;            // tS(D) = 50 ns
            @(negedge clk358);
            rdv = s_d; rd_driven = cart_drives_d;
            if (rd_driven && (rd_early !== rdv || ^rdv === 1'bx)) begin
                setup_viol = setup_viol + 1;
                $display("  [FAIL %0t] dato inestable en el muestreo del Z80: %02x -> %02x", $time, rd_early, rdv);
            end
            #85 iorq_n = 1'b1; rd_n = 1'b1;
        end
    endtask
    task io_rd(input [15:0] p);
        begin
            m1_fetch(16'h4002, 8'hDB);              // IN A,(n)
            io_rd_raw(p);
        end
    endtask

    // Lectura de E/S con los tiempos de un Z80 a 7,16 MHz (modo turbo): el dato se
    // muestrea ~259 ns despues de bajar /IORQ, en vez de ~620 ns.
    task io_rd_turbo(input [15:0] p);
        begin
            @(posedge clk358); #20 a = p;
            #120 iorq_n = 1'b0; #5 rd_n = 1'b0; t_iorq = $realtime;
            #(259.0 - 50.0 - 5.0) rd_early = s_d;
            #50.0 rdv = s_d; rd_driven = cart_drives_d;
            if (rd_driven && (rd_early !== rdv || ^rdv === 1'bx)) begin
                setup_viol = setup_viol + 1;
                $display("  [FAIL %0t] dato inestable en el muestreo (turbo): %02x -> %02x", $time, rd_early, rdv);
            end
            #45 iorq_n = 1'b1; rd_n = 1'b1;
            repeat (2) @(posedge clk358);
        end
    endtask

    task fm_w(input bank, input [7:0] r, input [7:0] v);
        begin
            io_wr({8'h00, bank ? 8'hC6 : 8'hC4}, r);
            io_wr({8'h00, bank ? 8'hC7 : 8'hC5}, v);
        end
    endtask
    task wv_w(input [7:0] r, input [7:0] v);
        begin io_wr(16'h007E, r); io_wr(16'h007F, v); end
    endtask
    task wv_r(input [7:0] r);
        begin io_wr(16'h007E, r); io_rd(16'h007F); end
    endtask
    task expect_silence(input [15:0] p, input [799:0] what);
        begin
            drive_seen = 1'b0;
            io_rd(p);
            ok(!drive_seen && rdv === 8'hFF, what);
        end
    endtask

    // ------------------------------------------------------------------
    //  Medida de relojes internos y del CE del motor PCM
    // ------------------------------------------------------------------
    task measure(input integer which, output real mhz);
        realtime t0, t1;
        integer  n;
        begin
            case (which)
                0: begin @(posedge fpga.u_top.clk_108m); t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.clk_108m); t1 = $realtime; end
                1: begin @(posedge fpga.u_top.clk_54m);  t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.clk_54m);  t1 = $realtime; end
                2: begin @(posedge fpga.u_top.clk_27m);  t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.clk_27m);  t1 = $realtime; end
                3: begin @(posedge fpga.u_top.clk_eng);  t0 = $realtime; for (n = 0; n < 700; n = n + 1) @(posedge fpga.u_top.clk_eng);  t1 = $realtime; end
                4: begin @(posedge fpga.u_top.u_av.clk_135m); t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.u_av.clk_135m); t1 = $realtime; end
                5: begin @(posedge fpga.u_top.u_av.clk_pix);  t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.u_av.clk_pix);  t1 = $realtime; end
                default: begin @(posedge fpga.u_top.u_av.clk_audio); t0 = $realtime; for (n = 0; n < 20; n = n + 1) @(posedge fpga.u_top.u_av.clk_audio); t1 = $realtime; end
            endcase
            mhz = (which == 3 ? 700.0 : which > 5 ? 20.0 : 200.0) * 1000.0 / (t1 - t0);
        end
    endtask
    function near(input real v, input real target, input real tol);
        near = (v > target * (1.0 - tol)) && (v < target * (1.0 + tol));
    endfunction

    // CE del motor: debe promediar 33,8688 MHz (44,1 kHz x 768)
    integer ce_cnt = 0;
    always @(posedge fpga.u_top.clk_eng) if (fpga.u_top.u_core.u_opl4pcm.ce === 1'b1) ce_cnt = ce_cnt + 1;

    // ------------------------------------------------------------------
    //  Audio: lo que entra al transmisor HDMI (aud_l / aud_r en cada clk_audio)
    // ------------------------------------------------------------------
    integer al_max, al_min, ar_max, ar_min, n_aud;
    task audio_clear;
        begin al_max = 0; al_min = 0; ar_max = 0; ar_min = 0; n_aud = 0; end
    endtask
    always @(posedge fpga.u_top.u_av.clk_audio) begin
        n_aud = n_aud + 1;
        if ($signed(fpga.u_top.u_av.aud_l) > al_max) al_max = $signed(fpga.u_top.u_av.aud_l);
        if ($signed(fpga.u_top.u_av.aud_l) < al_min) al_min = $signed(fpga.u_top.u_av.aud_l);
        if ($signed(fpga.u_top.u_av.aud_r) > ar_max) ar_max = $signed(fpga.u_top.u_av.aud_r);
        if ($signed(fpga.u_top.u_av.aud_r) < ar_min) ar_min = $signed(fpga.u_top.u_av.aud_r);
    end
    // la muestra no puede cambiar cerca del flanco en que el HDMI la toma
    realtime t_aud_chg = 0;
    integer  aud_unstable = 0;
    always @(fpga.u_top.u_av.aud_l or fpga.u_top.u_av.aud_r) t_aud_chg = $realtime;
    always @(posedge fpga.u_top.u_av.clk_audio) if ($realtime > 1000000 && ($realtime - t_aud_chg) < 5000.0) aud_unstable = aud_unstable + 1;

`ifdef WITH_HDMI_RX
`include "hdmi_rx_hookup.vh"
`endif

    // ------------------------------------------------------------------
    //  Volcado de cuadros de video (lo que pinta el vumetro) a PPM de texto
    // ------------------------------------------------------------------
    reg [23:0] fb [0:720*480-1];
    reg [9:0]  cx_q, cy_q;
    reg        dump_req = 1'b0, dumping = 1'b0;
    integer    fnum = 0, fd, px;
    reg [8*64-1:0] fname;
    always @(posedge fpga.u_top.u_av.clk_pix) begin
        cx_q <= fpga.u_top.u_av.cx; cy_q <= fpga.u_top.u_av.cy;
        if (dumping && cx_q < 720 && cy_q < 480) fb[cy_q * 720 + cx_q] = fpga.u_top.u_av.rgb;
        if (fpga.u_top.u_av.cx == 10'd0 && fpga.u_top.u_av.cy == 10'd0) begin
            if (dumping) begin
                $sformat(fname, "build/frame%0d.ppm", fnum);
                fd = $fopen(fname, "w");
                $fwrite(fd, "P3\n720 480\n255\n");
                for (px = 0; px < 720*480; px = px + 1)
                    $fwrite(fd, "%0d %0d %0d\n", fb[px][23:16], fb[px][15:8], fb[px][7:0]);
                $fclose(fd);
                $display("         cuadro volcado a %0s", fname);
                fnum = fnum + 1;
                dumping = 1'b0;
            end
            if (dump_req) begin dumping = 1'b1; dump_req = 1'b0; end
        end
    end
    task dump_frame;                    // pide el siguiente cuadro completo y espera a tenerlo
        begin
            dump_req = 1'b1;
            wait (dumping == 1'b1);
            wait (dumping == 1'b0);
        end
    endtask

    // ------------------------------------------------------------------
    //  La prueba
    // ------------------------------------------------------------------
    integer i, polls, n_ok, n_wr0, ce0;
    real    f;
    realtime t0;
    reg [7:0] exp;

    initial begin
        audio_clear;
        for (i = 0; i < 65536; i = i + 1) board.u_flash.mem[i] = i[7:0] ^ i[15:8] ^ 8'h5A;
        board.u_flash.mem[0]  = 8'h00;   // onda 0: 8 bits, inicio = 0x000100
        board.u_flash.mem[1]  = 8'h01;
        board.u_flash.mem[2]  = 8'h00;
        board.u_flash.mem[3]  = 8'h00;   // bucle = 0
        board.u_flash.mem[4]  = 8'h00;
        board.u_flash.mem[5]  = 8'hFF;   // fin = 64 muestras (complemento a 2)
        board.u_flash.mem[6]  = 8'hC0;
        board.u_flash.mem[7]  = 8'h00;
        board.u_flash.mem[8]  = 8'hF0;   // AR=15
        board.u_flash.mem[9]  = 8'h00;
        board.u_flash.mem[10] = 8'hFF;   // RC=15, RR=15
        board.u_flash.mem[11] = 8'h00;
        for (i = 0;  i < 32; i = i + 1) board.u_flash.mem[16'h0100 + i] = 8'h7F;
        for (i = 32; i < 64; i = i + 1) board.u_flash.mem[16'h0100 + i] = 8'h81;

        // ==============================================================
        $display("== A. arranque con el MSX APAGADO (lineas del slot a 0, sin reloj) ==");
        a = 16'hC4C4;
        wait (fpga.u_top.pll_locked === 1'b1);
        measure(0, f); ok(near(f, 108.0,  0.002), "clk_108m = 108 MHz");
        measure(1, f); ok(near(f, 54.0,   0.002), "clk_54m  = 54 MHz");
        measure(2, f); ok(near(f, 27.0,   0.002), "clk_27m  = 27 MHz (FM)");
        measure(4, f); ok(near(f, 135.0,  0.002), "clk_135m = 135 MHz (TMDS x5)");
        measure(5, f); ok(near(f, 27.0,   0.002), "clk_pix  = 27 MHz (pixel)");
        measure(3, f); ok(near(f, 38.5714, 0.002), "clk_eng  = 38,571 MHz (motor PCM, 135/3,5)");
        $display("         medido: %0.4f MHz", f);
        measure(6, f); ok(near(f * 1000.0, 48.0, 0.0005), "clk_audio = 48 kHz");
        $display("         medido: %0.4f kHz", f * 1000.0);

        wait (fpga.u_top.u_core.sdram_init_busy === 1'b0);
        fork : carga
            begin wait (fpga.u_top.u_core.wl_done === 1'b1); disable carga; end
            begin #40_000_000; disable carga; end
        join
        ok(fpga.u_top.u_core.wl_done === 1'b1, "el loader termina (YRW801 de la flash a la SDRAM)");
        $display("         carga terminada en t = %0.2f ms (%0d escrituras SDRAM)", $realtime / 1.0e6, sdram.n_wr);
        ok(fpga.u_top.u_core.wl_error === 1'b0, "el loader no agota reintentos");
        ok(sdram.n_wr == 4096, "4096 bytes escritos en la SDRAM, ni uno mas ni uno menos");
        #1_000;     // wl_badimg es combinacional de wl_done: que se asiente
        ok(fpga.u_top.u_core.wl_badimg === 1'b0, "la suma de la imagen copiada es la esperada");
        #300_000;
        ok(fpga.u_top.clk_alive === 1'b0, "sin reloj del slot: clk_alive = 0");
        ok(!drive_seen && pin[18] === 1'b1, "MSX apagado con IORQ=RD=0 en C4h: U3 sigue mirando a la FPGA");
        reset_n = 1'b1; #200_000;
        ok(!drive_seen, "RESET alto pero sin reloj: sigue sin conducir");

        // ==============================================================
        $display("== B. el MSX se enciende ==");
        mreq_n = 1'b1; iorq_n = 1'b1; rd_n = 1'b1; wr_n = 1'b1; m1_n = 1'b1; rfsh_n = 1'b1;
        sltsl_n = 1'b1; a = 16'h0000; reset_n = 1'b0;
        msx_on = 1'b1;
        #500_000 reset_n = 1'b1;
        fork : vivo
            begin wait (fpga.u_top.clk_alive === 1'b1); disable vivo; end
            begin #6_000_000; disable vivo; end
        join
        #100_000;
        ok(fpga.u_top.clk_alive === 1'b1, "con el reloj del slot: clk_alive = 1");
        ok(fpga.u_top.bus_reset_n_s === 1'b1, "/RESET del slot llega");

        // ==============================================================
        $display("== C. FM (C4h-C7h): estado, lectura de registros, deteccion ==");
        io_rd(16'h00C4);
        ok(rd_driven && (rdv & 8'hE0) == 8'h00, "IN C4h: la placa contesta, sin flags de timer");
        $display("         status = %02x", rdv);
        #60 ok(!cart_drives_d && pin[18] === 1'b1, "al acabar la lectura suelta el bus y U3 vuelve a mirar a la FPGA");
        fm_w(0, 8'h20, 8'h5A); io_wr(16'h00C4, 8'h20); io_rd(16'h00C5);
        ok(rdv === 8'h5A, "registro FM 020h: se relee 5Ah por C5h");
        fm_w(1, 8'h21, 8'hA5); io_wr(16'h00C6, 8'h21); io_rd(16'h00C7);
        ok(rdv === 8'hA5, "registro FM 121h: se relee A5h por C7h");
        io_wr(16'hA5C4, 8'h20); io_rd(16'h5AC5);
        ok(rdv === 8'h5A, "con A8-A15 a basura sigue decodificando por A0-A7");
        fm_w(1, 8'h05, 8'h03);                      // NEW = 1, NEW2 = 1
        wv_r(8'h02);
        ok(rdv === 8'h20, "registro wave 02h = 20h (identificador del YMF278B)");
        // (antes se lee OTRO registro, que vale 00h: sin el espejo, una lectura que
        //  llega tarde devuelve el dato de la lectura anterior, y si ese fuese
        //  tambien 20h la prueba pasaria por casualidad)
        io_wr(16'h007E, 8'h03); io_rd(16'h007F);
        ok(rdv === 8'h00, "registro wave 03h = 00h tras el reset");
        io_wr(16'h007E, 8'h02); io_rd_turbo(16'h007F);
        ok(rd_driven && rdv === 8'h20, "el identificador tambien se lee bien con los tiempos de un turbo a 7,16 MHz");
        io_rd_turbo(16'h00C4);
        ok(rd_driven && (rdv & 8'hE0) == 8'h00, "y el estado FM (C4h) tambien");
        $display("         la placa empieza a conducir como muy tarde %0.0f ns tras IORQ y suelta %0.0f ns tras subir /RD",
                 drv_lat_max, rel_max);
        ok(drv_lat_max < 200.0, "el dato esta en el bus con margen de sobra para el Z80 (lo mira a los ~620 ns)");
        ok(rel_max < 60.0, "suelta el bus en menos de 60 ns");

        // ==============================================================
        $display("== D. puertos y ciclos que NO son del MoonSound ==");
        expect_silence(16'h00C0, "IN C0h (MSX-Audio): silencio");
        expect_silence(16'h00C8, "IN C8h: silencio");
        expect_silence(16'h007C, "IN 7Ch (MSX-Music): silencio");
        expect_silence(16'h007D, "IN 7Dh: silencio");
        expect_silence(16'h00A8, "IN A8h (PPI): silencio");
        expect_silence(16'hC400, "IN con C4h en A8-A15 y 00h en A0-A7: silencio");
        drive_seen = 1'b0;
        @(posedge clk358); #100 a = 16'h40C4; sltsl_n = 1'b0;
        @(negedge clk358); #80 mreq_n = 1'b0; rd_n = 1'b0;
        repeat (2) @(posedge clk358);
        #90 mreq_n = 1'b1; rd_n = 1'b1; sltsl_n = 1'b1;
        repeat (2) @(posedge clk358);
        ok(!drive_seen, "lectura de memoria en 40C4h con /SLTSL: silencio");
        // reconocimiento de interrupcion: /IORQ + /M1, SIN /RD ni /WR, con C4h
        // en el bus de direcciones. Esta placa no ve /M1: no debe pasar nada.
        drive_seen = 1'b0;
        io_wr(16'h00C4, 8'h20);                     // deja seleccionado el registro 20h
        @(posedge clk358); #100 a = 16'h00C5; m1_n = 1'b0;
        repeat (2) @(posedge clk358); #75 iorq_n = 1'b0;
        repeat (2) @(posedge clk358);
        #90 iorq_n = 1'b1; m1_n = 1'b1;
        repeat (2) @(posedge clk358);
        ok(!drive_seen, "reconocimiento de interrupcion sobre C5h: no conduce");
        io_wr(16'h00C4, 8'h20); io_rd(16'h00C5);
        ok(rdv === 8'h5A, "y no ha escrito nada en el registro seleccionado");

        if (STOP_AFTER <= 4) begin
            ok(bad_drive == 0, "U3 nunca miro al MSX fuera de una lectura nuestra");
            ok(bad_oe == 0, "la FPGA nunca condujo datos contra U3");
            ok(setup_viol == 0, "ningun dato cambio dentro de la ventana de muestreo del Z80");
            fin;
        end

        // ==============================================================
        $display("== E. timer 1 del OPL3: por sondeo (esta placa no tiene /INT) ==");
        fm_w(0, 8'h02, 8'hFF);
        fm_w(0, 8'h04, 8'h01);
        #400_000;
        io_rd(16'h00C4);
        ok((rdv & 8'hC0) == 8'hC0, "el flag del timer 1 se lee por C4h (IRQ + FT1)");
        $display("         status = %02x", rdv);
        ok(j2_1 === 1'b0 && j2_8 === 1'b0, "pines del zocalo ESP en reposo (salidas opcionales desactivadas)");
        fm_w(0, 8'h04, 8'h00);
        fm_w(0, 8'h04, 8'h80);
        io_rd(16'h00C4);
        ok((rdv & 8'hE0) == 8'h00, "y se borra con el reset de flags");

        // ==============================================================
        $display("== F. wavetable SIN /WAIT: YRW801 por los registros 03h-06h ==");
        wv_w(8'h02, 8'h01);                         // MEMMODE = 1
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
        wv_r(8'h06); ok(rdv === 8'h00, "YRW801[000000]");
        io_rd(16'h007F); ok(rdv === 8'h01, "YRW801[000001] (autoincremento)");
        io_rd(16'h007F); ok(rdv === 8'h00, "YRW801[000002]");
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h01); wv_w(8'h05, 8'h00);
        wv_r(8'h06); ok(rdv === 8'h7F, "YRW801[000100] (primera muestra)");
        // rafaga de 48 lecturas seguidas, al ritmo de un INIR (21 estados T)
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h0A); wv_w(8'h05, 8'h37);
        io_wr(16'h007E, 8'h06);
        n_ok = 0;
        for (i = 0; i < 48; i = i + 1) begin
            exp = (8'h37 + i) ^ 8'h0A ^ 8'h5A;
            repeat (16) @(posedge clk358);          // 16 + 5 del ciclo de E/S = 21 T
            io_rd_raw(16'h007F);
            if (rdv === exp) n_ok = n_ok + 1;
            else $display("         lectura %0d: %02x, esperado %02x", i, rdv, exp);
        end
        $display("         rafaga tipo INIR sin /WAIT: %0d de 48 lecturas correctas", n_ok);
        ok(n_ok == 48, "rafaga de lecturas de la memoria de ondas sin /WAIT (motor en reposo)");

        $display("== G. RAM de muestras (0x200000) en la SDRAM ==");
        wv_w(8'h03, 8'h20); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
        wv_w(8'h06, 8'hA5); io_wr(16'h007F, 8'h5A); io_wr(16'h007F, 8'hC3);
        wv_w(8'h03, 8'h20); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
        wv_r(8'h06);     ok(rdv === 8'hA5, "RAM[200000] = A5h");
        io_rd(16'h007F); ok(rdv === 8'h5A, "RAM[200001] = 5Ah");
        io_rd(16'h007F); ok(rdv === 8'hC3, "RAM[200002] = C3h");
        wv_w(8'h02, 8'h00);

        // relectura de registros de slot por 7Fh, sin /WAIT, a 3,58 MHz: el chip real
        // devuelve lo escrito a la primera (hasta el 05/10/2026 el motor devolvia a
        // menudo el valor del registro leido justo antes)
        $display("== G2. relectura de registros de slot (50h-5Bh) por 7Fh, sin /WAIT ==");
        for (i = 0; i < 12; i = i + 1) wv_w(8'h50 + i, 8'h13 + 8'h14 * i);
        polls = 0;
        for (i = 0; i < 12; i = i + 1) begin
            wv_r(8'h50 + i);
            exp = 8'h13 + 8'h14 * i;
            if (rdv !== exp) begin
                polls = polls + 1;
                $display("         registro %02x: escrito %02x, leido %02x", 8'h50 + i[7:0], exp, rdv);
            end
        end
        ok(polls == 0, "cada registro de slot se relee a la primera tal como se escribio");
        polls = 0;
        for (i = 0; i < 12; i = i + 1) begin
            wv_r(8'h50 + i); io_rd(16'h007F);
            exp = 8'h13 + 8'h14 * i;
            if (rdv !== exp) polls = polls + 1;
        end
        ok(polls == 0, "y leyendo cada uno dos veces seguidas, tambien la segunda");

        if (STOP_AFTER <= 7) begin
            ok(sdram.n_err == 0, "la SDRAM no vio ninguna orden ilegal");
            ok(bad_oe == 0, "la FPGA nunca condujo datos contra U3");
            fin;
        end

        // ==============================================================
        $display("== H. nota PCM (onda 0) -> motor -> mezcla -> audio HDMI ==");
        wv_w(8'h20, 8'h00); wv_w(8'h38, 8'h00); wv_w(8'h50, 8'h01);
        wv_w(8'h08, 8'h00);
        polls = 0;
        io_rd(16'h00C4);
        while (rdv[1] && polls < 200) begin #20_000; io_rd(16'h00C4); polls = polls + 1; end
        ok(!rdv[1], "flag LD del status se limpia (cabecera leida de la SDRAM)");
        wv_w(8'h68, 8'h80);                         // KEY ON, centro
        audio_clear; ce0 = ce_cnt; t0 = $realtime;
        #3_000_000;
        f = (ce_cnt - ce0) * 1000.0 / ($realtime - t0);
        $display("         audio hacia el HDMI: L max=%0d min=%0d | R max=%0d min=%0d | %0d muestras",
                 al_max, al_min, ar_max, ar_min, n_aud);
        ok(al_max > 8000 && al_min < -8000 && ar_max > 8000 && ar_min < -8000, "la nota PCM llega a los dos canales del HDMI");
        ok(n_aud > 140 && n_aud < 148, "a 48 kHz");
        // con la nota SONANDO: rafaga de lecturas de la YRW801 sin /WAIT, a ritmo
        // normal y con tiempos de turbo (el motor esta ocupado leyendo muestras)
        wv_w(8'h02, 8'h01);
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h0B); wv_w(8'h05, 8'h10);
        io_wr(16'h007E, 8'h06);
        n_ok = 0;
        for (i = 0; i < 32; i = i + 1) begin
            exp = (8'h10 + i) ^ 8'h0B ^ 8'h5A;
            repeat (16) @(posedge clk358);
            io_rd_raw(16'h007F);
            if (rdv === exp) n_ok = n_ok + 1;
            else $display("         lectura %0d (sonando): %02x, esperado %02x", i, rdv, exp);
        end
        ok(n_ok == 32, "32 lecturas de la memoria de ondas con la nota sonando, sin /WAIT");
        n_ok = 0;
        for (i = 32; i < 64; i = i + 1) begin
            exp = (8'h10 + i) ^ 8'h0B ^ 8'h5A;
            repeat (4) @(posedge clk358);
            io_rd_turbo(16'h007F);
            if (rdv === exp) n_ok = n_ok + 1;
            else $display("         lectura %0d (turbo, sonando): %02x, esperado %02x", i, rdv, exp);
        end
        ok(n_ok == 32, "y otras 32 con tiempos de turbo a 7,16 MHz");
        wv_w(8'h02, 8'h00);
        $display("         CE del motor PCM: %0.4f MHz de media (objetivo 33,8688)", f);
        ok(near(f, 33.8688, 0.001), "el motor PCM va a su ritmo con el reloj de 38,57 MHz (44,1 kHz x 768)");

        // ==============================================================
        $display("== I. nota FM (canal 0) con panoramica: el HDMI es ESTEREO ==");
        fm_w(0, 8'h20, 8'h01); fm_w(0, 8'h23, 8'h01);
        fm_w(0, 8'h40, 8'h3F); fm_w(0, 8'h43, 8'h00);
        fm_w(0, 8'h60, 8'hF0); fm_w(0, 8'h63, 8'hF0);
        fm_w(0, 8'h80, 8'h00); fm_w(0, 8'h83, 8'h00);
        fm_w(0, 8'hC0, 8'h11);                             // FM solo IZQUIERDA
        fm_w(0, 8'hA0, 8'h44); fm_w(0, 8'hB0, 8'h32);      // KEY ON
        wv_w(8'h68, 8'h40);                                // PCM: KEY OFF + DAMP
        #3_000_000; audio_clear; #3_000_000;
        $display("         FM a la izquierda: L max=%0d min=%0d | R max=%0d min=%0d", al_max, al_min, ar_max, ar_min);
        ok(al_max > 1000 && al_min < -1000, "FM con pan a la izquierda: suena por el canal izquierdo del HDMI");
        ok(ar_max < 50 && ar_min > -50, "y el derecho queda en silencio");

        // ==============================================================
        $display("== J. el vumetro: cuadro de video con FM a la izquierda y PCM sonando ==");
        wv_w(8'h68, 8'h80);                                // PCM otra vez
        for (i = 0; i < FRAMES; i = i + 1) dump_frame;
        $display("         niveles (segmentos de 28): FM L=%0d R=%0d | WAVE L=%0d R=%0d | OUT L=%0d R=%0d",
                 fpga.u_top.u_av.vu_level[4:0],   fpga.u_top.u_av.vu_level[9:5],
                 fpga.u_top.u_av.vu_level[14:10], fpga.u_top.u_av.vu_level[19:15],
                 fpga.u_top.u_av.vu_level[24:20], fpga.u_top.u_av.vu_level[29:25]);
        ok(fpga.u_top.u_av.vu_level[4:0] > 5'd10 && fpga.u_top.u_av.vu_level[9:5] == 5'd0, "barra FM: izquierda con nivel, derecha a cero");
        ok(fpga.u_top.u_av.vu_level[14:10] > 5'd20 && fpga.u_top.u_av.vu_level[19:15] > 5'd20, "barras WAVE: las dos con nivel alto");
        ok(fpga.u_top.u_av.vu_level[24:20] >= fpga.u_top.u_av.vu_level[14:10], "barra OUT izquierda: al menos lo que marca WAVE");

        // ==============================================================
        $display("== K. /RESET del MSX: el chip se reinicia, la YRW801 se queda ==");
        n_wr0 = sdram.n_wr;
        reset_n = 1'b0; #500_000; reset_n = 1'b1; #1_000_000;
        ok(fpga.u_top.u_core.wl_done === 1'b1 && sdram.n_wr == n_wr0, "no se recarga la YRW801");
        fm_w(1, 8'h05, 8'h03);
        wv_w(8'h02, 8'h01);
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h01); wv_w(8'h05, 8'h20);
        wv_r(8'h06); ok(rdv === 8'h81, "YRW801[000120] sigue en la SDRAM tras el reset");

        // ==============================================================
        $display("== L. salud general ==");
        ok(bad_drive == 0, "U3 nunca miro al MSX fuera de una lectura nuestra");
        ok(bad_oe == 0, "la FPGA nunca condujo datos contra U3");
        ok(setup_viol == 0, "ningun dato cambio dentro de la ventana de muestreo del Z80");
        ok(aud_unstable == 0, "las muestras de audio llevan quietas >= 5 us cuando el HDMI las toma");
        ok(sdram.n_err == 0, "la SDRAM no vio ninguna orden ilegal");
        ok(sdram.n_ref > 1000, "la SDRAM recibe refresco");
        ok(fpga.u_top.u_core.sd_timeout === 1'b0, "el watchdog del puente SDRAM no llego a saltar");
`ifdef WITH_HDMI_RX
        hdmi_final_checks;
`endif
        fin;
    end

    initial begin
        #600_000_000;
        $display("RESULTADO: FAIL (timeout global, %0d errores hasta aqui)", errors);
        $finish;
    end
endmodule

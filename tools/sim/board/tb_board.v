// ============================================================================
// tb_board.v — MoonTANG ENTERO sobre un modelo de la WonderTANG 2.0b / 2.02b.
//
// Que se simula: el top real (convertido con sv2v), con los rPLL y CLKDIV de
// la libreria de simulacion de Gowin, conectado POR NUMERO DE PIN (envoltorio
// generado del .cst) a un modelo de la placa cuyos pines salen del firmware
// oficial; la flash SPI con una YRW801 sintetica; la SDRAM embebida; y un Z80
// a 3,58 MHz que hace ciclos de bus con su temporizacion real.
//
// Que demuestra si pasa: que el .cst casa con la placa, que el barrido del bus
// multiplexado decodifica bien direcciones y control, que la direccion de datos,
// /BUSDIR, /WAIT e /INT tienen la polaridad correcta, que la cadena
// flash -> SDRAM -> motor PCM -> I2S funciona, y que el cartucho no toca el bus
// cuando no debe. Lo que NO puede demostrar: la electronica (niveles, la
// alimentacion, la soldadura de J3) ni el oido.
//
// Controles negativos (run_board.sh): el .cst de agosto y la captura original
// de la SDRAM TIENEN que fallar aqui; si pasaran, el banco no valdria nada.
// ============================================================================
`timescale 1ns/1ps

module tb_board;
    parameter real    T_FPGA_CO  = 4.0;     // reloj -> pad de la FPGA (barrido de holgura)
    parameter integer CAPTURE    = 1;       // SDRAM: 1 = captura en clk, 0 = original
    parameter integer AUDIO_MONO = 1;
    parameter integer QUIET      = 0;
    parameter integer STOP_AFTER = 99;      // corta tras la fase N (4 = D, 6 = F): controles y barrido
    parameter integer HDMI       = 0;       // 1 = variante con HDMI (moontang_wt_hdmi_top)
    parameter integer BLANK      = 0;       // 1 = flash en blanco (todo FF) en vez de la YRW801

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
    tri1       s_wait_n, s_int_n;           // pull-ups del MSX
    wire       s_busdir_n;

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

    defparam fpga.u_top.AUDIO_MONO = AUDIO_MONO;
    defparam fpga.u_top.SDRAM_RD_CAPTURE_CLK = CAPTURE;
    moontang_pins fpga (
        .pin(pin),
        .O_sdram_clk(sd_clk), .O_sdram_cke(sd_cke), .O_sdram_cs_n(sd_cs_n),
        .O_sdram_ras_n(sd_ras_n), .O_sdram_cas_n(sd_cas_n), .O_sdram_wen_n(sd_we_n),
        .IO_sdram_dq(sd_dq), .O_sdram_addr(sd_a), .O_sdram_ba(sd_ba), .O_sdram_dqm(sd_dqm)
    );
    // 4 KB de "YRW801" bastan para la prueba (la carga entera son 2 MB de SPI)
    defparam fpga.u_top.u_wt.u_core.u_loader.WAVE_SIZE = 23'h001000;
    // ...y la espera de arranque de la flash (185 ms en la placa) se acorta
    defparam fpga.u_top.u_wt.u_core.u_flash.STARTUP_WAIT = 32'd2000;
    // ...y la suma esperada es la de esos 4 KB sinteticos (la de la YRW801 de
    // verdad, 101FDA0Eh, la lleva el RTL por defecto)
    defparam fpga.u_top.u_wt.u_core.u_loader.EXPECTED_SUM = 32'h0007FFAD;

    sdram_model sdram (
        .clk(sd_clk), .cke(sd_cke), .cs_n(sd_cs_n), .ras_n(sd_ras_n), .cas_n(sd_cas_n),
        .we_n(sd_we_n), .addr(sd_a), .ba(sd_ba), .dqm(sd_dqm), .dq(sd_dq)
    );

    wire signed [15:0] spk, i2s_l, i2s_r;
    wire        i2s_frame, led, cart_drives_d;
    wt20x_board #(.T_FPGA_CO(T_FPGA_CO)) board (
        .pin(pin),
        .s_a(a), .s_d(s_d),
        .s_mreq_n(mreq_n), .s_iorq_n(iorq_n), .s_rd_n(rd_n), .s_wr_n(wr_n),
        .s_reset_n(reset_n), .s_m1_n(m1_n), .s_rfsh_n(rfsh_n),
        .s_cs1_n(1'b1), .s_cs2_n(1'b1), .s_cs12_n(1'b1),
        .s_sltsl_n(sltsl_n), .s_clock(clk358),
        .s_wait_n(s_wait_n), .s_int_n(s_int_n), .s_busdir_n(s_busdir_n),
        .spk(spk), .i2s_l(i2s_l), .i2s_r(i2s_r), .i2s_frame(i2s_frame),
        .led(led), .cart_drives_d(cart_drives_d)
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
    //  Vigilante del bus de datos: la placa solo puede conducir D0-D7 durante
    //  una lectura de E/S de un puerto del MoonSound, con el MSX vivo.
    // ------------------------------------------------------------------
    wire [7:0] port = a[7:0];
    wire ours = (port[7:2] == 6'b110001) || (port[7:1] == 7'b0111111);
    wire legit_rd = msx_on && reset_n && !iorq_n && !rd_n && m1_n && ours;
    integer bad_drive = 0;
    reg     drive_seen = 1'b0;
    always @(posedge cart_drives_d) begin
        drive_seen = 1'b1;
        if (!legit_rd) begin
            bad_drive = bad_drive + 1;
            $display("  [FAIL %0t] la placa conduce D0-D7 sin que le lean: A=%04x iorq=%b rd=%b wr=%b m1=%b mreq=%b on=%b",
                     $time, a, iorq_n, rd_n, wr_n, m1_n, mreq_n, msx_on);
        end
    end
    // ...y /BUSDIR tiene que acompañar siempre a la conduccion
    integer bad_busdir = 0;
    always @(cart_drives_d) #20 if (cart_drives_d !== ~s_busdir_n) bad_busdir = bad_busdir + 1;

    // ------------------------------------------------------------------
    //  Ciclos de bus del Z80 (3,58 MHz, tiempos del Z80A)
    // ------------------------------------------------------------------
    integer  last_tw;               // estados TW extra del ultimo ciclo de E/S
    realtime t_iorq, t_wait;        // para medir la latencia de /WAIT
    reg      wait_early, waiting;
    integer  setup_viol = 0;
    integer  wait_rel_amb = 0;            // sueltas de /WAIT dentro de tS(WAIT) (informativo)
    real     wait_lat = 0, wait_lat_max = 0;
    always @(negedge s_wait_n) begin
        t_wait = $realtime;
        wait_lat = t_wait - t_iorq;
        if (wait_lat > wait_lat_max) wait_lat_max = wait_lat;
    end

    // ciclo M1 (busqueda de opcode) + refresco: otro dispositivo pone el dato
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

    task io_wait_states;            // TW* automatico + los que pida /WAIT
        begin
            @(posedge clk358);                      // TW*
            last_tw = 0; waiting = 1'b1;
            while (waiting) begin
                #(TH - 70.0) wait_early = s_wait_n; // tS(WAIT) = 70 ns
                @(negedge clk358);
                // Si /WAIT se ACTIVA dentro de tS(WAIT) el Z80 podria no esperar: error.
                // Si se SUELTA dentro, el Z80 hace un estado de espera de mas o de menos;
                // el banco sigue por el camino corto (decide en el flanco) y el dato se
                // comprueba ahi, asi que los dos casos quedan cubiertos. La suelta pasa por
                // un NPN y el pull-up del MSX: su retardo real no se conoce y ninguna
                // alineacion en la FPGA garantiza el margen; se cuenta como informacion.
                if (wait_early !== s_wait_n) begin
                    if (wait_early === 1'b0 && s_wait_n === 1'b1) begin
                        wait_rel_amb = wait_rel_amb + 1;
                        if (!QUIET) $display("  [info %0t] /WAIT se suelta dentro de tS(WAIT) = 70 ns (puerto %02x, %0.0f ns tras /IORQ): el Z80 puede hacer un estado de espera de mas",
                                             $time, a[7:0], $realtime - t_iorq);
                    end
                    else begin
                        setup_viol = setup_viol + 1;
                        $display("  [FAIL %0t] /WAIT cambio dentro de tS(WAIT) = 70 ns: %b -> %b (puerto %02x, %0.0f ns tras /IORQ)",
                                 $time, wait_early, s_wait_n, a[7:0], $realtime - t_iorq);
                    end
                end
                if (s_wait_n === 1'b0) begin
                    last_tw = last_tw + 1;
                    @(posedge clk358);
                end
                else waiting = 1'b0;
            end
        end
    endtask

    task io_wr(input [15:0] p, input [7:0] v);
        begin
            m1_fetch(16'h4000, 8'hD3);              // OUT (n),A
            @(posedge clk358); #110 a = p;
            @(negedge clk358); #100 d_out = v; d_oe = 1'b1;
            @(posedge clk358); #75 iorq_n = 1'b0; #5 wr_n = 1'b0; t_iorq = $realtime;
            io_wait_states;
            @(posedge clk358);                      // T3
            @(negedge clk358); #80 wr_n = 1'b1; iorq_n = 1'b1;
            #60 d_oe = 1'b0;
        end
    endtask

    reg [7:0] rdv, rd_early;
    reg       rd_driven;
    task io_rd(input [15:0] p);
        begin
            m1_fetch(16'h4002, 8'hDB);              // IN A,(n)
            @(posedge clk358); #110 a = p;
            @(posedge clk358); #75 iorq_n = 1'b0; #10 rd_n = 1'b0; t_iorq = $realtime;
            io_wait_states;
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

    task fm_w(input bank, input [7:0] r, input [7:0] v);     // registro FM
        begin
            io_wr({8'h00, bank ? 8'hC6 : 8'hC4}, r);
            io_wr({8'h00, bank ? 8'hC7 : 8'hC5}, v);
        end
    endtask
    task wv_w(input [7:0] r, input [7:0] v);                 // registro wave
        begin io_wr(16'h007E, r); io_wr(16'h007F, v); end
    endtask
    task wv_r(input [7:0] r);
        begin io_wr(16'h007E, r); io_rd(16'h007F); end
    endtask

    // lectura que NO debe contestar nadie
    task expect_silence(input [15:0] p, input [799:0] what);
        begin
            drive_seen = 1'b0;
            io_rd(p);
            ok(!drive_seen && rdv === 8'hFF, what);
        end
    endtask

    // ------------------------------------------------------------------
    //  Medida de relojes internos
    // ------------------------------------------------------------------
    task measure(input integer which, output real mhz);
        realtime t0, t1;
        integer  n;
        begin
            case (which)
                0: begin @(posedge fpga.u_top.u_wt.clk_108m); t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.u_wt.clk_108m); t1 = $realtime; end
                1: begin @(posedge fpga.u_top.u_wt.clk_54m);  t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.u_wt.clk_54m);  t1 = $realtime; end
                2: begin @(posedge fpga.u_top.u_wt.clk_27m);  t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.u_wt.clk_27m);  t1 = $realtime; end
                3: begin @(posedge fpga.u_top.u_wt.clk_eng);  t0 = $realtime; for (n = 0; n < 700; n = n + 1) @(posedge fpga.u_top.u_wt.clk_eng);  t1 = $realtime; end
                4: begin @(posedge fpga.u_top.u_wt.clk_dac);  t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.u_wt.clk_dac);  t1 = $realtime; end
                5: begin @(posedge fpga.u_top.u_wt.clk_21m);  t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge fpga.u_top.u_wt.clk_21m);  t1 = $realtime; end
                default: begin @(posedge sd_clk); t0 = $realtime; for (n = 0; n < 200; n = n + 1) @(posedge sd_clk); t1 = $realtime; end
            endcase
            mhz = (which == 3 ? 700.0 : 200.0) * 1000.0 / (t1 - t0);
        end
    endtask
    function near(input real v, input real target, input real tol);
        near = (v > target * (1.0 - tol)) && (v < target * (1.0 + tol));
    endfunction

    // ------------------------------------------------------------------
    //  Monitores de audio
    // ------------------------------------------------------------------
    integer fml_max, fml_min, fmr_max, fmr_min, pcm_max, pcm_min, spk_max, spk_min;
    integer n_frames = 0, n_lr_diff = 0;
    task audio_clear;
        begin
            fml_max = 0; fml_min = 0; fmr_max = 0; fmr_min = 0;
            pcm_max = 0; pcm_min = 0; spk_max = 0; spk_min = 0;
        end
    endtask
    always @(posedge fpga.u_top.u_wt.clk_54m) begin
        if ($signed(fpga.u_top.u_wt.u_core.opl4fm_wav_l) > fml_max) fml_max = $signed(fpga.u_top.u_wt.u_core.opl4fm_wav_l);
        if ($signed(fpga.u_top.u_wt.u_core.opl4fm_wav_l) < fml_min) fml_min = $signed(fpga.u_top.u_wt.u_core.opl4fm_wav_l);
        if ($signed(fpga.u_top.u_wt.u_core.opl4fm_wav_r) > fmr_max) fmr_max = $signed(fpga.u_top.u_wt.u_core.opl4fm_wav_r);
        if ($signed(fpga.u_top.u_wt.u_core.opl4fm_wav_r) < fmr_min) fmr_min = $signed(fpga.u_top.u_wt.u_core.opl4fm_wav_r);
        if ($signed(fpga.u_top.u_wt.u_core.opl4pcm_l)    > pcm_max) pcm_max = $signed(fpga.u_top.u_wt.u_core.opl4pcm_l);
        if ($signed(fpga.u_top.u_wt.u_core.opl4pcm_l)    < pcm_min) pcm_min = $signed(fpga.u_top.u_wt.u_core.opl4pcm_l);
    end
    always @(i2s_frame) begin
        n_frames = n_frames + 1;
        if (i2s_l !== i2s_r) n_lr_diff = n_lr_diff + 1;
        if (spk > spk_max) spk_max = spk;
        if (spk < spk_min) spk_min = spk;
    end

`ifdef WITH_HDMI_RX
`include "hdmi_rx_hookup.vh"
`endif

    // sl_stride y sl_hi (prefetch del motor) no tienen reset: en la FPGA nacen a
    // 0 (valor de encendido de la BSRAM/registros), en la simulacion a X.
    integer ii_sl;
    initial begin
        #1;
        for (ii_sl = 0; ii_sl < 32; ii_sl = ii_sl + 1) begin
            fpga.u_top.u_wt.u_core.u_opl4pcm.sl_stride[ii_sl] = 3'd0;
            fpga.u_top.u_wt.u_core.u_opl4pcm.sl_hi[ii_sl] = 3'd0;
        end
    end

    // ------------------------------------------------------------------
    //  La prueba
    // ------------------------------------------------------------------
    integer i, polls, n_ref0;
    real    f;
    realtime t_ref0;
    reg [7:0] exp;
    reg      int_seen;

    initial begin
        audio_clear;
        // ---- YRW801 sintetica en la flash (0x200000) ----
        for (i = 0; i < 65536; i = i + 1) board.u_flash.mem[i] = i[7:0] ^ i[15:8] ^ 8'h5A;
        board.u_flash.mem[0]  = 8'h00;   // onda 0: 8 bits, inicio = 0x000100
        board.u_flash.mem[1]  = 8'h01;
        board.u_flash.mem[2]  = 8'h00;
        board.u_flash.mem[3]  = 8'h00;   // bucle = 0
        board.u_flash.mem[4]  = 8'h00;
        board.u_flash.mem[5]  = 8'hFF;   // fin = 64 muestras (complemento a 2)
        board.u_flash.mem[6]  = 8'hC0;
        board.u_flash.mem[7]  = 8'h00;   // LFO/VIB
        board.u_flash.mem[8]  = 8'hF0;   // AR=15
        board.u_flash.mem[9]  = 8'h00;
        board.u_flash.mem[10] = 8'hFF;   // RC=15, RR=15
        board.u_flash.mem[11] = 8'h00;
        for (i = 0;  i < 32; i = i + 1) board.u_flash.mem[16'h0100 + i] = 8'h7F;
        for (i = 32; i < 64; i = i + 1) board.u_flash.mem[16'h0100 + i] = 8'h81;
        if (BLANK) for (i = 0; i < 65536; i = i + 1) board.u_flash.mem[i] = 8'hFF;

        // ==============================================================
        $display("== A. arranque con el MSX APAGADO (lineas del slot a 0, sin reloj) ==");
        // Peor caso de SlotDoctor: la Tang con USB y el MSX apagado. Las lineas
        // a 0 parecen exactamente una lectura (IORQ=0, RD=0); aqui ademas se
        // pone la direccion de un puerto nuestro.
        a = 16'hC4C4; m1_n = 1'b1;
        wait (fpga.u_top.u_wt.pll_locked === 1'b1);
        measure(0, f); ok(near(f, 108.0,  0.002), "clk_108m = 108 MHz");
        $display("         medido: %0.3f MHz", f);
        measure(1, f); ok(near(f, 54.0,   0.002), "clk_54m  = 54 MHz");
        measure(2, f); ok(near(f, 27.0,   0.002), "clk_27m  = 27 MHz (FM)");
        measure(3, f);
        if (HDMI) ok(near(f, 38.5714, 0.002), "clk_eng  = 38,571 MHz (motor PCM, de los 135 MHz del HDMI)");
        else      ok(near(f, 37.125,  0.002), "clk_eng  = 37,125 MHz (motor PCM)");
        $display("         medido: %0.4f MHz", f);
        measure(5, f); ok(near(f, 21.6,   0.002), "clk_21m  = 21,6 MHz");
        measure(4, f); ok(near(f, 1.5429, 0.002), "clk_dac  = 1,543 MHz (BCLK del I2S)");
        $display("         medido: %0.4f MHz -> fs = %0.1f Hz", f, f * 1.0e6 / 32.0);
        measure(6, f); ok(near(f, 108.0,  0.002), "reloj de la SDRAM = 108 MHz");

        wait (fpga.u_top.u_wt.u_core.sdram_init_busy === 1'b0);
        $display("         SDRAM iniciada en t = %0.1f us", $realtime / 1000.0);
        fork : carga
            begin wait (fpga.u_top.u_wt.u_core.wl_done === 1'b1); disable carga; end
            begin #40_000_000; disable carga; end
        join
        ok(fpga.u_top.u_wt.u_core.wl_done === 1'b1, "el loader termina (YRW801 de la flash a la SDRAM)");
        $display("         carga terminada en t = %0.2f ms (%0d escrituras SDRAM)", $realtime / 1.0e6, sdram.n_wr);
        ok(fpga.u_top.u_wt.u_core.wl_error === 1'b0, "el loader no agota reintentos");
        ok(fpga.u_top.u_wt.u_core.sd_timeout === 1'b0, "el puente SDRAM no dispara el watchdog");
        ok(sdram.n_wr == 4096, "4096 bytes escritos en la SDRAM, ni uno mas ni uno menos");
        #1_000;     // wl_badimg es combinacional de wl_done: que se asiente
        if (BLANK) begin
            // flash en blanco: la copia termina, pero la suma no casa y se avisa
            ok(fpga.u_top.u_wt.u_core.wl_badimg === 1'b1, "flash en blanco: la suma no casa y se marca la imagen como no valida");
            #2_000_000;
            ok(fpga.u_top.u_wt.u_core.wl_done === 1'b1, "  sin bloquear el motor (el FM sigue funcionando)");
            if (HDMI) begin
                #100_000;
                ok(fpga.u_top.u_av.st_rom_s1 === 2'd3, "  y la pantalla dice YRW801 NO VALIDA");
            end
            fin;
        end
        ok(fpga.u_top.u_wt.u_core.wl_badimg === 1'b0, "la suma de la imagen copiada es la esperada");
        #300_000;
        ok(fpga.u_top.u_wt.clk_alive === 1'b0, "sin reloj del slot: clk_alive = 0");
        ok(!drive_seen, "MSX apagado con IORQ=RD=0 en C4h: la placa NO conduce D0-D7");
        ok(s_wait_n === 1'b1 && s_int_n === 1'b1, "MSX apagado: /WAIT e /INT sueltos");

        // el MSX arranca: /RESET alto pero aun sin reloj -> sigue callada
        reset_n = 1'b1; #200_000;
        ok(!drive_seen, "RESET alto pero sin reloj: sigue sin conducir");

        // ==============================================================
        $display("== B. el MSX se enciende ==");
        mreq_n = 1'b1; iorq_n = 1'b1; rd_n = 1'b1; wr_n = 1'b1; m1_n = 1'b1; rfsh_n = 1'b1;
        sltsl_n = 1'b1; a = 16'h0000; reset_n = 1'b0;
        msx_on = 1'b1;
        #500_000 reset_n = 1'b1;
        fork : vivo
            begin wait (fpga.u_top.u_wt.clk_alive === 1'b1); disable vivo; end
            begin #6_000_000; disable vivo; end
        join
        #100_000;
        ok(fpga.u_top.u_wt.clk_alive === 1'b1, "con el reloj del slot: clk_alive = 1");
        ok(fpga.u_top.u_wt.bus_reset_n === 1'b1, "/RESET del slot llega (bit 4 del grupo de control)");
        ok(led === 1'b1, "LED fijo: todo listo");

        // ==============================================================
        $display("== C. FM (C4h-C7h): estado, lectura de registros, deteccion ==");
        io_rd(16'h00C4);
        ok(rd_driven && (rdv & 8'hE0) == 8'h00, "IN C4h: la placa contesta, sin flags de timer");
        $display("         status = %02x", rdv);
        #40 ok(s_busdir_n === 1'b1 && !cart_drives_d, "al acabar la lectura suelta el bus y /BUSDIR vuelve a 1");
        fm_w(0, 8'h20, 8'h5A); io_wr(16'h00C4, 8'h20); io_rd(16'h00C5);
        ok(rdv === 8'h5A, "registro FM 020h: se relee 5Ah por C5h");
        fm_w(1, 8'h21, 8'hA5); io_wr(16'h00C6, 8'h21); io_rd(16'h00C7);
        ok(rdv === 8'hA5, "registro FM 121h: se relee A5h por C7h");
        // el byte alto de la direccion no pinta nada en E/S (IN A,(C) pone B)
        io_wr(16'hA5C4, 8'h20); io_rd(16'h5AC5);
        ok(rdv === 8'h5A, "con A8-A15 a basura sigue decodificando por A0-A7");

        fm_w(1, 8'h05, 8'h03);                      // NEW = 1, NEW2 = 1
        wv_r(8'h02);
        ok(rdv === 8'h20, "registro wave 02h = 20h (identificador del YMF278B)");

        // ==============================================================
        $display("== D. puertos y ciclos que NO son del MoonSound ==");
        expect_silence(16'h00C0, "IN C0h (MSX-Audio): silencio");
        expect_silence(16'h00C8, "IN C8h: silencio");
        expect_silence(16'h007C, "IN 7Ch (MSX-Music): silencio");
        expect_silence(16'h007D, "IN 7Dh: silencio");
        expect_silence(16'h00A8, "IN A8h (PPI): silencio");
        expect_silence(16'hC400, "IN con C4h en A8-A15 y 00h en A0-A7: silencio");
        expect_silence(16'h7F12, "IN con 7Fh en A8-A15: silencio");
        // lectura de MEMORIA en xxC4h con /SLTSL activo
        drive_seen = 1'b0;
        @(posedge clk358); #100 a = 16'h40C4; sltsl_n = 1'b0;
        @(negedge clk358); #80 mreq_n = 1'b0; rd_n = 1'b0;
        repeat (2) @(posedge clk358);
        #90 mreq_n = 1'b1; rd_n = 1'b1; sltsl_n = 1'b1;
        repeat (2) @(posedge clk358);
        ok(!drive_seen, "lectura de memoria en 40C4h con /SLTSL: silencio");
        // ciclo con /M1 activo (reconocimiento de interrupcion) sobre C4h
        drive_seen = 1'b0;
        @(posedge clk358); #100 a = 16'h00C4; m1_n = 1'b0;
        repeat (2) @(posedge clk358); #75 iorq_n = 1'b0; rd_n = 1'b0;
        repeat (2) @(posedge clk358);
        #90 iorq_n = 1'b1; rd_n = 1'b1; m1_n = 1'b1;
        repeat (2) @(posedge clk358);
        ok(!drive_seen, "IORQ con /M1 activo sobre C4h: silencio");

        if (STOP_AFTER <= 4) begin
            ok(bad_drive == 0, "la placa nunca condujo D0-D7 fuera de una lectura suya");
            ok(setup_viol == 0, "ningun dato cambio dentro de la ventana de muestreo del Z80");
            fin;
        end

        // ==============================================================
        $display("== E. timer 1 del OPL3 -> /INT del slot ==");
        ok(s_int_n === 1'b1, "/INT en reposo antes de arrancar el timer");
        fm_w(0, 8'h02, 8'hFF);                      // timer 1: un tick (80 us)
        fm_w(0, 8'h04, 8'h01);                      // ST1 = 1, sin mascara
        int_seen = 1'b0;
        fork : espera_int
            begin wait (s_int_n === 1'b0); int_seen = 1'b1; disable espera_int; end
            begin #1_500_000; disable espera_int; end
        join
        ok(int_seen, "/INT del slot baja al desbordar el timer 1");
        io_rd(16'h00C4);
        ok((rdv & 8'hC0) == 8'hC0, "status: IRQ + FT1");
        $display("         status = %02x", rdv);
        fm_w(0, 8'h04, 8'h00);                      // timer parado
        fm_w(0, 8'h04, 8'h80);                      // RST de flags
        #600_000;
        ok(s_int_n === 1'b1, "/INT se suelta tras el reset de flags");

        // ==============================================================
        $display("== F. wavetable: YRW801 por los registros 03h-06h, con /WAIT ==");
        wv_w(8'h02, 8'h01);                         // MEMMODE = 1
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
        t_wait = 0;
        wv_r(8'h06); ok(rdv === 8'h00, "YRW801[000000]");
        io_rd(16'h007F); ok(rdv === 8'h01, "YRW801[000001] (autoincremento)");
        io_rd(16'h007F); ok(rdv === 8'h00, "YRW801[000002]");
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h01); wv_w(8'h05, 8'h00);
        wv_r(8'h06); ok(rdv === 8'h7F, "YRW801[000100] (primera muestra)");
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h0A); wv_w(8'h05, 8'h37);
        for (i = 0; i < 6; i = i + 1) begin
            exp = (8'h37 + i) ^ 8'h0A ^ 8'h5A;
            if (i == 0) wv_r(8'h06); else io_rd(16'h007F);
            ok(rdv === exp, "YRW801[000A37+i] = contenido de la flash");
        end
        ok(t_wait != 0, "/WAIT del slot se ha usado en las lecturas wave");
        $display("         /WAIT del slot baja como muy tarde %0.0f ns tras IORQ (el Z80 lo mira a los ~345 ns)", wait_lat_max);
        ok(wait_lat_max < 270.0, "/WAIT llega con holgura al muestreo del Z80 a 3,58 MHz");

        $display("== G. RAM de muestras (0x200000) en la SDRAM ==");
        wv_w(8'h03, 8'h20); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
        wv_w(8'h06, 8'hA5); io_wr(16'h007F, 8'h5A); io_wr(16'h007F, 8'hC3);
        wv_w(8'h03, 8'h20); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
        wv_r(8'h06);     ok(rdv === 8'hA5, "RAM[200000] = A5h");
        io_rd(16'h007F); ok(rdv === 8'h5A, "RAM[200001] = 5Ah");
        io_rd(16'h007F); ok(rdv === 8'hC3, "RAM[200002] = C3h");
        wv_w(8'h02, 8'h00);                         // MEMMODE fuera

        // relectura de registros de slot por 7Fh, respetando /WAIT: el chip real
        // devuelve lo escrito a la primera (hasta el 05/10/2026 el motor devolvia a
        // menudo el valor del registro leido justo antes)
        $display("== G2. relectura de registros de slot (50h-5Bh) por 7Fh ==");
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
            fin;
        end

        // ==============================================================
        $display("== H. nota PCM (onda 0) -> motor -> mezcla -> I2S -> altavoz ==");
        wv_w(8'h20, 8'h00); wv_w(8'h38, 8'h00); wv_w(8'h50, 8'h01);
        wv_w(8'h08, 8'h00);                         // onda 0: carga la cabecera
        polls = 0;
        io_rd(16'h00C4);
        while (rdv[1] && polls < 200) begin #20_000; io_rd(16'h00C4); polls = polls + 1; end
        ok(!rdv[1], "flag LD del status se limpia (cabecera leida de la SDRAM)");
        wv_w(8'h68, 8'h80);                         // KEY ON, centro
        audio_clear; n_frames = 0; n_lr_diff = 0;
        #3_000_000;
        $display("         PCM del motor: max=%0d min=%0d | altavoz: max=%0d min=%0d | tramas I2S=%0d",
                 pcm_max, pcm_min, spk_max, spk_min, n_frames);
        ok(pcm_max > 2000 && pcm_min < -2000, "el motor PCM reproduce la onda");
        ok(spk_max > 500 && spk_min < -500, "y llega al amplificador de la Tang por I2S");
        ok(n_frames > 120, "tramas I2S a ~48 kHz");
        // (las tramas L y R se cargan con 10 us de diferencia: no tienen por que
        //  ser iguales; que el mono lleva LOS DOS canales se comprueba en la fase I)
        wv_w(8'h68, 8'h40);                         // KEY OFF + DAMP
        #2_500_000; audio_clear; #400_000;
        ok(spk_max < 200 && spk_min > -200, "KEY OFF: silencio");

        // ==============================================================
        $display("== I. nota FM (canal 0) con panoramica ==");
        fm_w(0, 8'h20, 8'h01); fm_w(0, 8'h23, 8'h01);      // MULT = 1
        fm_w(0, 8'h40, 8'h3F); fm_w(0, 8'h43, 8'h00);      // moduladora muda, portadora a tope
        fm_w(0, 8'h60, 8'hF0); fm_w(0, 8'h63, 8'hF0);      // AR = 15
        fm_w(0, 8'h80, 8'h00); fm_w(0, 8'h83, 8'h00);
        fm_w(0, 8'hC0, 8'h11);                             // solo IZQUIERDA, aditivo
        fm_w(0, 8'hA0, 8'h44); fm_w(0, 8'hB0, 8'h32);      // KEY ON
        #1_000_000; audio_clear; #3_000_000;
        $display("         FM izquierda: L max=%0d min=%0d | R max=%0d min=%0d | altavoz max=%0d min=%0d",
                 fml_max, fml_min, fmr_max, fmr_min, spk_max, spk_min);
        ok(fml_max > 1000 && fml_min < -1000, "FM con pan a la izquierda: suena por L");
        ok(fmr_max == 0 && fmr_min == 0, "y R queda en silencio (estereo del MSXimus Z)");
        ok(spk_max > 300 && spk_min < -300, "en mono el altavoz la reproduce (a la mitad)");
        fm_w(0, 8'hC0, 8'h21);                             // solo DERECHA
        #1_000_000; audio_clear; #3_000_000;
        ok(fmr_max > 1000 && fmr_min < -1000 && fml_max == 0 && fml_min == 0, "FM con pan a la derecha: solo R");
        if (AUDIO_MONO)
            ok(spk_max > 300 && spk_min < -300, "y TAMBIEN se oye por el ampli mono (no se pierde medio MoonSound)");
        fm_w(0, 8'hB0, 8'h12);                             // KEY OFF

        // ==============================================================
        $display("== J. /RESET del MSX: el chip se reinicia, la YRW801 se queda ==");
        n_ref0 = sdram.n_wr;
        reset_n = 1'b0; #500_000; reset_n = 1'b1; #1_000_000;
        ok(fpga.u_top.u_wt.u_core.wl_done === 1'b1 && sdram.n_wr == n_ref0, "no se recarga la YRW801");
        fm_w(1, 8'h05, 8'h03);
        wv_w(8'h02, 8'h01);
        wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h01); wv_w(8'h05, 8'h20);
        wv_r(8'h06); ok(rdv === 8'h81, "YRW801[000120] sigue en la SDRAM tras el reset");

        // ==============================================================
        // La cadena de memoria sobrevive al /RESET del MSX y su toggle de "hecho"
        // puede quedar a 1. Antes del arreglo, al soltar el reset el motor veia un
        // "hecho" falso y metia en su cache, como YRW801[000000], la ultima palabra
        // leida antes del reset. Se fuerza ese caso (toggle a 1 y una palabra
        // distinta como ultima lectura) y se lee [000000]/[000001] 96 veces.
        $display("== J2. /RESET con la cadena de memoria a mitad de su toggle ==");
        wv_w(8'h03, 8'h20); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
        wv_w(8'h06, 8'h55); io_wr(16'h007F, 8'h55);
        wv_w(8'h03, 8'h20); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
        wv_r(8'h06);                                // la ultima palabra leida: 5555h
        i = 0;
        while (fpga.u_top.u_wt.u_core.u_wave.eng_done_t !== 1'b1 && i < 8) begin
            wv_w(8'h06, 8'h55); i = i + 1;          // cada escritura cambia el toggle
            #200_000;
        end
        ok(fpga.u_top.u_wt.u_core.u_wave.eng_done_t === 1'b1, "toggle de la cadena de memoria a 1 antes del reset");
        reset_n = 1'b0; #500_000; reset_n = 1'b1; #1_000_000;
        fm_w(1, 8'h05, 8'h03);
        wv_w(8'h02, 8'h01);
        polls = 0;
        for (i = 0; i < 96; i = i + 1) begin
            wv_w(8'h03, 8'h00); wv_w(8'h04, 8'h00); wv_w(8'h05, 8'h00);
            wv_r(8'h06);     if (rdv !== 8'h00) polls = polls + 1;
            io_rd(16'h007F); if (rdv !== 8'h01) polls = polls + 1;
        end
        $display("         %0d de 192 lecturas distintas de lo esperado", polls);
        ok(polls == 0, "tras el /RESET, YRW801[000000] y [000001] se leen bien las 96 veces");
        wv_w(8'h02, 8'h00);

        // ==============================================================
        $display("== K. salud general ==");
        ok(bad_drive == 0, "la placa nunca condujo D0-D7 fuera de una lectura suya");
        ok(bad_busdir == 0, "/BUSDIR acompaño siempre a la conduccion del bus");
        ok(setup_viol == 0, "ningun dato cambio en la ventana de muestreo del Z80 y /WAIT nunca se activo dentro");
        $display("         sueltas de /WAIT dentro de tS(WAIT): %0d (el Z80 hace un estado de espera de mas o de menos; inofensivo)", wait_rel_amb);
        ok(sdram.n_err == 0, "la SDRAM no vio ninguna orden ilegal");
        ok(sdram.n_ref > 1000, "la SDRAM recibe refresco");
        $display("         SDRAM: %0d ACT, %0d RD, %0d WR, %0d REF en %0.1f ms (un refresco cada %0.1f us)",
                 sdram.n_act, sdram.n_rd, sdram.n_wr, sdram.n_ref, $realtime / 1.0e6,
                 $realtime / 1000.0 / sdram.n_ref);
        ok(fpga.u_top.u_wt.u_core.sd_timeout === 1'b0, "el watchdog del puente SDRAM no llego a saltar");

`ifdef WITH_HDMI_RX
        // el HDMI va en paralelo con el audio del MSX: se espera a tener un cuadro
        // completo en el cable y se comprueba con el receptor de verificacion
        fork : cuadro_hdmi
            begin wait (rx.n_cuadros >= 1); disable cuadro_hdmi; end
            begin #45_000_000; disable cuadro_hdmi; end
        join
        $display("         vumetro (segmentos de 28): FM L=%0d R=%0d | WAVE L=%0d R=%0d | OUT L=%0d R=%0d",
                 fpga.u_top.u_av.vu_level[4:0],   fpga.u_top.u_av.vu_level[9:5],
                 fpga.u_top.u_av.vu_level[14:10], fpga.u_top.u_av.vu_level[19:15],
                 fpga.u_top.u_av.vu_level[24:20], fpga.u_top.u_av.vu_level[29:25]);
        hdmi_final_checks;
`endif
        fin;
    end

    initial begin
        #400_000_000;
        $display("RESULTADO: FAIL (timeout global, %0d errores hasta aqui)", errors);
        $finish;
    end
endmodule

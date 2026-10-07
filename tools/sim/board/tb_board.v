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
//
// Con -DWITH_Y8950 (run_board.sh audio) el top es moontang_wt_audio_top y el
// banco comprueba ademas el MSX-Audio (fase L); con -Ptb_board.BUSV=1 hace en
// su lugar la fase M (bus, turbo, IRQ y /RESET del Y8950) tras la fase D.
// Con -DWITH_Y8950 -DWITH_HDMI_RX -DWITH_VU_Y8950 y HDMI = 1 (run_board.sh
// hdmi_audio) el top es el EXPERIMENTAL moontang_wt_hdmi_audio_top: las
// comprobaciones de las dos y ademas la barra MSX-AUDIO del vumetro (fase V).
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
    // 1 = (solo con -DWITH_Y8950) tras la fase D, la fase M y fin: turbo a 3,58 /
    //     5,37 / 7,16 / 10,74 MHz en C0h/C1h frente a C4h, /WR cortos, ruido de
    //     bus (INTA, memoria, M1, refresco, otros puertos) sin efecto en el
    //     Y8950, /INT del OPL3 y del Y8950 en AND y /RESET a mitad de un IN/OUT C1h
    parameter integer BUSV       = 0;

    localparam real TH = 139.6825;          // medio periodo de 3,579545 MHz
`ifdef WITH_Y8950
    localparam integer Y8950 = 1;           // variante con MSX-Audio (moontang_wt_audio_top)
`else
    localparam integer Y8950 = 0;
`endif

    // ------------------------------------------------------------------
    //  El MSX
    // ------------------------------------------------------------------
    reg        msx_on = 1'b0;
    reg        clk358 = 1'b0;
    always #(TH) if (msx_on) clk358 = ~clk358; else clk358 = 1'b0;
    integer    z80_cyc = 0;                 // ciclos del Z80 (fase frente a la FPGA: fase L4b)
    always @(posedge clk358) z80_cyc = z80_cyc + 1;

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
    wire ours = (port[7:2] == 6'b110001) || (port[7:1] == 7'b0111111) ||
                (Y8950 && port[7:1] == 7'b1100000);          // C0h-C1h (MSX-Audio)
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
    //  Ciclos de E/S de un Z80 mas rapido (turbo): periodo TT. Direccion en T1,
    //  /IORQ y /RD (o /WR) bajan 0,3 T despues del flanco de subida de T2, el
    //  Z80 mira /WAIT en la bajada de TW (1,5 T tras T2) y el dato en la bajada
    //  de T3 (2,5 T tras T2); /WR sube ahi. Entre ciclo y ciclo, 4 T sin E/S
    //  (la busqueda de la instruccion). No se siguen estados de espera: si el
    //  cartucho pide /WAIT se cuenta en fast_wait.
    // ------------------------------------------------------------------
    // Lo que se mide en cada lectura rapida: si el dato estaba quieto los 50 ns
    // de antes del muestreo (fast_stable) y cuanto tardo el bus en tomar su
    // valor final desde que bajo /IORQ (fast_lat). No cuenta en setup_viol:
    // es una medida que se compara entre puertos (fase L6).
    integer  fast_wait = 0;
    reg      fast_stable;
    real     fast_lat;
    realtime t_sd_chg = 0;
    always @(s_d) t_sd_chg = $realtime;
    task io_rd_fast(input [15:0] p, input real TT);
        begin
            #(TT) a = p;
            #(1.3 * TT) iorq_n = 1'b0; rd_n = 1'b0; t_iorq = $realtime;
            #(1.2 * TT) if (s_wait_n !== 1'b1) fast_wait = fast_wait + 1;
            #(1.0 * TT - 50.0) rd_early = s_d;
            #50.0 rdv = s_d; rd_driven = cart_drives_d;
            fast_stable = (rd_early === rdv) && (^rdv !== 1'bx);
            fast_lat = t_sd_chg - t_iorq;
            #(0.3 * TT) iorq_n = 1'b1; rd_n = 1'b1;
            #(4.0 * TT);
        end
    endtask
    // n lecturas rapidas de un puerto, comparando con el valor esperado
    integer  fr_bad, fr_unst;
    real     fr_lat;
    task fast_reads(input [15:0] p, input integer n, input [7:0] expv, input real TT);
        integer k;
        begin
            fr_bad = 0; fr_unst = 0; fr_lat = 0.0;
            for (k = 0; k < n; k = k + 1) begin
                io_rd_fast(p, TT);
                if (!rd_driven || rdv !== expv) fr_bad = fr_bad + 1;
                if (!fast_stable) fr_unst = fr_unst + 1;
                if (fast_lat > fr_lat) fr_lat = fast_lat;
            end
        end
    endtask
    task io_wr_fast(input [15:0] p, input [7:0] v, input real TT, input real T_WR);
        begin
            #(TT) a = p; d_out = v; d_oe = 1'b1;
            #(1.3 * TT) iorq_n = 1'b0; wr_n = 1'b0; t_iorq = $realtime;
            #(T_WR) wr_n = 1'b1; iorq_n = 1'b1;
            #(0.3 * TT) d_oe = 1'b0;
            #(4.0 * TT);
        end
    endtask

    // ------------------------------------------------------------------
    //  MSX-Audio: registros (C0h = indice, C1h = dato) y la RAM del ADPCM
    // ------------------------------------------------------------------
    // Tras escribir un dato en un registro de operador o de canal (20h y
    // siguientes), el Y8950 real pide 23 us (84 ciclos de su reloj) antes de la
    // siguiente escritura: jtopl lo actualiza cuando le llega el turno a esa
    // ranura. El software de verdad espera; el banco tambien.
    task y_w(input [7:0] r, input [7:0] v);
        begin
            io_wr(16'h00C0, r); io_wr(16'h00C1, v);
            if (r >= 8'h20) #25_000;
        end
    endtask
    function [7:0] y_pat(input [7:0] seed, input integer k);
        y_pat = (seed + k[7:0] * 8'h1D) ^ {k[2:0], 5'b00000};
    endfunction

    function [21:0] gray22bin(input [21:0] gray);
        integer bitn;
        begin
            gray22bin[21] = gray[21];
            for (bitn = 20; bitn >= 0; bitn = bitn - 1)
                gray22bin[bitn] = gray22bin[bitn + 1] ^ gray[bitn];
        end
    endfunction
    // ventana [start, start + n) de la RAM de muestras (n multiplo de 4)
    task y_window(input [17:0] start, input integer n);
        reg [17:0] last;
        begin
            last = start + n - 1;
            y_w(8'h07, 8'h01);                          // RESET del ADPCM
            y_w(8'h08, 8'h00);                          // RAM, 256 KB
            y_w(8'h09, start[9:2]);  y_w(8'h0A, start[17:10]);
            y_w(8'h0B, last[9:2]);   y_w(8'h0C, last[17:10]);
        end
    endtask
    task y_upload(input [17:0] start, input integer n, input [7:0] seed);
        integer k;
        begin
            y_window(start, n);
            y_w(8'h07, 8'h60);                          // CPU -> RAM
            io_wr(16'h00C0, 8'h0F);
            for (k = 0; k < n; k = k + 1) io_wr(16'h00C1, y_pat(seed, k));
            y_w(8'h07, 8'h01);
        end
    endtask
    task y_readback(input [17:0] start, input integer n, input [7:0] seed, output integer nbad);
        integer k;
        begin
            y_window(start, n);
            y_w(8'h07, 8'h20);                          // RAM -> CPU
            io_wr(16'h00C0, 8'h0F);
            io_rd(16'h00C1); io_rd(16'h00C1);           // las dos lecturas de relleno
            nbad = 0;
            for (k = 0; k < n; k = k + 1) begin
                io_rd(16'h00C1);
                if (rdv !== y_pat(seed, k)) begin
                    nbad = nbad + 1;
                    if (nbad <= 3) $display("         ADPCM[%05x] = %02x, esperado %02x", start + k, rdv, y_pat(seed, k));
                end
            end
            y_w(8'h07, 8'h01);
        end
    endtask
    // byte de la RAM del ADPCM tal como esta en el modelo de la SDRAM (banco 2)
    function [7:0] sd_adpcm(input [17:0] b);
        reg [31:0] w;
        begin
            w = sdram.mem[{2'b10, 3'b000, b[17:2]}];
            sd_adpcm = w[8 * b[1:0] +: 8];
        end
    endfunction

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
    localparam integer OPL4_RESTO = 16;     // FM del OPL4 "callado": |x| <= 16 (ver fase L)
    integer n_frames = 0, n_lr_diff = 0;
    task audio_clear;
        begin
            fml_max = 0; fml_min = 0; fmr_max = 0; fmr_min = 0;
            pcm_max = 0; pcm_min = 0; spk_max = 0; spk_min = 0;
            yfm_max = 0; yfm_min = 0; yad_max = 0; yad_min = 0;
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
    integer yfm_max = 0, yfm_min = 0, yad_max = 0, yad_min = 0;
`ifdef WITH_Y8950
    always @(posedge fpga.u_top.u_wt.clk_54m) begin
        if ($signed(fpga.u_top.u_wt.u_core.y8950_fm)    > yfm_max) yfm_max = $signed(fpga.u_top.u_wt.u_core.y8950_fm);
        if ($signed(fpga.u_top.u_wt.u_core.y8950_fm)    < yfm_min) yfm_min = $signed(fpga.u_top.u_wt.u_core.y8950_fm);
        if ($signed(fpga.u_top.u_wt.u_core.y8950_adpcm) > yad_max) yad_max = $signed(fpga.u_top.u_wt.u_core.y8950_adpcm);
        if ($signed(fpga.u_top.u_wt.u_core.y8950_adpcm) < yad_min) yad_min = $signed(fpga.u_top.u_wt.u_core.y8950_adpcm);
    end
`endif
    always @(i2s_frame) begin
        n_frames = n_frames + 1;
        if (i2s_l !== i2s_r) n_lr_diff = n_lr_diff + 1;
        if (spk > spk_max) spk_max = spk;
        if (spk < spk_min) spk_min = spk;
    end

`ifdef WITH_HDMI_RX
`include "hdmi_rx_hookup.vh"
`endif

`ifdef WITH_VU_Y8950
    // ------------------------------------------------------------------
    //  Barra MSX-AUDIO del vumetro (variante EXPERIMENTAL wt_hdmi_audio,
    //  -DWITH_VU_Y8950, con -DWITH_Y8950 y -DWITH_HDMI_RX). Modelo propio de
    //  la barra, independiente de vu_screen: en sus 24 filas (y = 248..271) y
    //  en los 16 px de cada uno de sus 28 segmentos (x = 168 + 18 (k-1) + 0..15)
    //  el pixel que sale hacia el cable tiene que ser el color que toca segun
    //  el nivel y la marca de pico de ese momento (marca > encendido > apagado;
    //  verde 1-20, amarillo 21-25, rojo 26-28), y en los 2 px de hueco entre
    //  segmentos, el fondo.
    //  Ademas: la barra solo se mueve con el Y8950 (antes de la fase L, con el
    //  OPL4 sonando, se queda a 0 mientras OUT se mueve) y se enciende con la
    //  nota FM de la fase L4.
    // ------------------------------------------------------------------
    function [7:0] vu_lim8(input [7:0] c);
        vu_lim8 = 8'd16 + (c * 16'd219 + 16'd127) / 16'd255;
    endfunction
    function [23:0] vu_lim(input [23:0] c);
        vu_lim = {vu_lim8(c[23:16]), vu_lim8(c[15:8]), vu_lim8(c[7:0])};
    endfunction
    function [23:0] vu_color(input integer k, input integer lvl, input integer pk);
        integer z;
        begin
            z = (k >= 26) ? 2 : (k >= 21) ? 1 : 0;
            if (k == pk)
                vu_color = vu_lim(z == 2 ? 24'hFFA090 : z == 1 ? 24'hFFF8A0 : 24'hB0FFC0);
            else if (k <= lvl)
                vu_color = vu_lim(z == 2 ? 24'hF03020 : z == 1 ? 24'hF0D020 : 24'h20E040);
            else
                vu_color = vu_lim(z == 2 ? 24'h2A0C08 : z == 1 ? 24'h2A2608 : 24'h0A2410);
        end
    endfunction
    reg     fase_L = 1'b0;
    integer vuy_pcx = 1023, vuy_pcy = 1023, vuy_k, vuy_lvl, vuy_pk;
    integer vuy_seg_ok = 0, vuy_seg_mal = 0, vuy_filas_altas = 0;
    integer vuy_max_antes = 0, vuy_out_max_antes = 0, vuy_max = 0, vuy_hueco_ok = 0;
    reg [23:0] vuy_esp;
    always @(negedge fpga.u_top.u_av.clk_pix) begin
        if (vuy_pcy >= 248 && vuy_pcy < 248 + 24 && vuy_pcx >= 168 && vuy_pcx < 168 + 28 * 18 - 2
            && fpga.u_top.u_av.rst_n_pix) begin
            vuy_k   = (vuy_pcx - 168) / 18 + 1;
            vuy_lvl = fpga.u_top.u_av.vu_level[34:30];
            vuy_pk  = fpga.u_top.u_av.vu_peak[34:30];
            vuy_esp = ((vuy_pcx - 168) % 18 < 16) ? vu_color(vuy_k, vuy_lvl, vuy_pk) : vu_lim(24'h06080E);
            if (fpga.u_top.u_av.rgb === vuy_esp) begin
                vuy_seg_ok = vuy_seg_ok + 1;
                if ((vuy_pcx - 168) % 18 >= 16) vuy_hueco_ok = vuy_hueco_ok + 1;
            end
            else begin
                vuy_seg_mal = vuy_seg_mal + 1;
                if (vuy_seg_mal <= 4)
                    $display("  [vu] barra MSX-AUDIO, (%0d,%0d) segmento %0d (nivel %0d, pico %0d): %06h, esperado %06h",
                             vuy_pcx, vuy_pcy, vuy_k, vuy_lvl, vuy_pk, fpga.u_top.u_av.rgb, vuy_esp);
            end
            if (vuy_pcy == 260 && vuy_pcx == 168 + 27 * 18 + 8 && vuy_lvl >= 20) vuy_filas_altas = vuy_filas_altas + 1;
        end
        vuy_pcx = fpga.u_top.u_av.cx;
        vuy_pcy = fpga.u_top.u_av.cy;
    end
    always @(posedge fpga.u_top.u_wt.clk_54m) begin
        if (fpga.u_top.u_av.vu_level[34:30] > vuy_max) vuy_max = fpga.u_top.u_av.vu_level[34:30];
        if (!fase_L) begin
            if (fpga.u_top.u_av.vu_level[34:30] > vuy_max_antes) vuy_max_antes = fpga.u_top.u_av.vu_level[34:30];
            if (fpga.u_top.u_av.vu_level[24:20] > vuy_out_max_antes) vuy_out_max_antes = fpga.u_top.u_av.vu_level[24:20];
        end
    end
    integer vuy_fd;
    task vu_y8950_checks;
        begin
            $display("== V. barra MSX-AUDIO del vumetro ==");
            // la nota de L4 se ve en el cuadro siguiente; se espera a tener la
            // barra alta en pantalla y despues un cuadro entero en el cable con ella
            fork : barra_alta
                begin wait (vuy_filas_altas >= 1); disable barra_alta; end
                begin #40_000_000; disable barra_alta; end
            join
            if (vuy_filas_altas >= 1) begin
                fork : cuadro_barra
                    begin @(posedge hrx_nuevo_cuadro); @(posedge hrx_nuevo_cuadro); disable cuadro_barra; end
                    begin #40_000_000; disable cuadro_barra; end
                join
                // con QUIET = 1 (el control negativo 6, que corre a la vez) no se
                // escribe: es el mismo fichero
                if (!QUIET) begin
                    vuy_fd = $fopen("build/hdmi_audio_cuadro.ppm", "w");
                    rx.escribir_ppm(vuy_fd);
                    $fclose(vuy_fd);
                end
            end
            $display("         MSX-AUDIO: nivel max %0d (antes de la fase L: %0d, con OUT a %0d) | pixeles de la barra comprobados %0d bien (%0d de hueco), %0d mal, %0d cuadros enteros | cuadros con la barra >= 20: %0d",
                     vuy_max, vuy_max_antes, vuy_out_max_antes, vuy_seg_ok, vuy_hueco_ok, vuy_seg_mal,
                     vuy_seg_ok / (24 * (28 * 18 - 2)), vuy_filas_altas);
            ok(vuy_out_max_antes >= 10 && vuy_max_antes == 0, "MSX-AUDIO: quieta mientras solo suena el OPL4 (OUT si se mueve)");
            ok(vuy_max >= 20, "MSX-AUDIO: la nota FM del Y8950 (fase L4) la sube a 20 segmentos o mas");
            ok(vuy_filas_altas >= 1, "MSX-AUDIO: se pinta alta en pantalla");
            ok(vuy_seg_mal == 0 && vuy_seg_ok >= 3 * 24 * (28 * 18 - 2),
               "MSX-AUDIO: cada pixel de la barra con su color (nivel, pico, zona y hueco), 3 cuadros o mas");
        end
    endtask
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

`ifdef WITH_Y8950
    // Lo mismo en el interpolador del ADPCM (jt10_adpcmb_interpol y su divisor,
    // de jotego): sus registros de datos no tienen reset. En la FPGA nacen a 0;
    // en la simulacion, a X, y la primera reproduccion ADPCM tras el encendido
    // (fase L3) sacaba un par de muestras X a la mezcla (pcminter <= pcmlast
    // antes de que pcmlast tenga dato; step antes de la primera division). El
    // banco de HDMI las ve (el transmisor toma una muestra con X).
    initial begin
        #1;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.pcmlast        = 16'sd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.delta_x        = 16'sd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.pre_dx         = 17'sd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.deltan         = 4'd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.pre_dn         = 4'd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.adv2           = 6'd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.pcminter       = 16'sd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.step           = 16'd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.step_sign      = 1'b0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.next_step_sign = 1'b0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.u_div.d        = 16'd0;
        fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_adpcm.u_interpol.u_div.r        = 16'd0;
    end
`endif

    // ==================== verificacion de bus (fase M, BUSV=1) ====================
    integer tb_in_c1 = 0, tb_out_c0 = 0, tb_out_c1 = 0;
    always @(negedge rd_n) #1 if (msx_on && reset_n && !iorq_n && m1_n && a[7:0] == 8'hC1) tb_in_c1 = tb_in_c1 + 1;
    always @(negedge wr_n) #1 if (msx_on && reset_n && !iorq_n && m1_n && a[7:0] == 8'hC0) tb_out_c0 = tb_out_c0 + 1;
    always @(negedge wr_n) #1 if (msx_on && reset_n && !iorq_n && m1_n && a[7:0] == 8'hC1) tb_out_c1 = tb_out_c1 + 1;
    integer du_rdc1 = 0, du_wrc0 = 0, du_wrc1 = 0;
`ifdef WITH_Y8950
`define YY fpga.u_top.u_wt.u_core.g_y8950.u_y8950
    always @(posedge fpga.u_top.u_wt.clk_54m) begin
        if (`YY.rd_c1 === 1'b1 && reset_n) du_rdc1 = du_rdc1 + 1;
        if (`YY.wr_c0 === 1'b1 && reset_n) du_wrc0 = du_wrc0 + 1;
        if (`YY.wr_c1 === 1'b1 && reset_n) du_wrc1 = du_wrc1 + 1;
    end
`endif
    task cnt_clear; begin tb_in_c1 = 0; tb_out_c0 = 0; tb_out_c1 = 0; du_rdc1 = 0; du_wrc0 = 0; du_wrc1 = 0; end endtask
    task cnt_report(input [799:0] what);
        begin
            $display("         contadores: IN C1h banco=%0d rd_c1=%0d | OUT C0h banco=%0d wr_c0=%0d | OUT C1h banco=%0d wr_c1=%0d",
                     tb_in_c1, du_rdc1, tb_out_c0, du_wrc0, tb_out_c1, du_wrc1);
            ok(tb_in_c1 == du_rdc1 && tb_out_c0 == du_wrc0 && tb_out_c1 == du_wrc1, what);
        end
    endtask
    integer m_i, m_k, m_w, m_bad, m_unst, m_minw_y, m_minw_o, m_nb, m_bad_o, m_unst_o;
    real    m_tt, m_lat_o, m_lat_y;
    reg [18:0] m_ptr0;
    reg [7:0]  m_v, m_rsel, m_d0;
    reg        m_ok_y, m_ok_o, m_int;

    // ------------------------------------------------------------------
    //  La prueba
    // ------------------------------------------------------------------
    integer i, k, polls, n_ref0, nb, nb2, n_wr0, n_fw0, n_ok;
    real    f, tt;
    reg [7:0] st_y;
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

`ifdef TEST_HDMI_LOCK_GLITCH
        // Una perdida corta del PLL HDMI solo puede parar/resetear su propio
        // dominio (pixel + motor PCM).  El cartucho no debe resetear SDRAM ni
        // recargar los 2 MiB de YRW801: en la placa real eso parecia una pausa
        // de varios segundos cada vez que lock_hdmi tenia un glitch.
        if (HDMI) begin
            n_ref0 = sdram.n_wr;
            $display("== A2. perdida transitoria de lock_hdmi ==");
            force fpga.u_top.lock_hdmi = 1'b0;
            #20_000;
            ok(fpga.u_top.u_wt.u_core.por_reset_n === 1'b1,
               "lock_hdmi bajo no resetea SDRAM, loader ni el bus");
            ok(fpga.u_top.u_wt.u_core.wl_done === 1'b1 && sdram.n_wr == n_ref0,
               "lock_hdmi bajo no reinicia la copia YRW801");
            release fpga.u_top.lock_hdmi;
            #20_000;
            ok(fpga.u_top.u_wt.u_core.por_reset_n === 1'b1 &&
               fpga.u_top.u_wt.u_core.wl_done === 1'b1 && sdram.n_wr == n_ref0,
               "al volver lock_hdmi la tarjeta conserva su estado");
        end
`endif
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
        if (Y8950) begin
            // con el MSX-Audio, C0h-C1h si son nuestros (fase L); C2h-C3h (la
            // segunda unidad) no
            drive_seen = 1'b0;
            io_rd(16'h00C0);
            ok(drive_seen && rd_driven && rdv === 8'h06, "IN C0h (MSX-Audio): status del Y8950 tras el reset = 06h");
            $display("         status = %02x", rdv);
            expect_silence(16'h00C2, "IN C2h (segunda unidad de MSX-Audio): silencio");
            expect_silence(16'h00C3, "IN C3h: silencio");
        end
        else
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

`ifdef WITH_Y8950
        if (BUSV) begin
        // ==============================================================
        $display("== M. bus, temporizacion e IRQ del Y8950 (BUSV = 1) ==");
        cnt_clear;
        // ---- M1. turbo: 3,58 / 5,37 / 7,16 / 10,74 MHz ----
        y_upload(18'h05000, 16, 8'h3A);
        fm_w(0, 8'h2A, 8'h5C);
        for (m_i = 0; m_i < 4; m_i = m_i + 1) begin
            m_tt = (m_i == 0) ? 279.365 : (m_i == 1) ? 186.243 : (m_i == 2) ? 139.682 : 93.122;
            $display("         -- %0.2f MHz (T = %0.1f ns): muestreo %0.0f ns tras /IORQ --", 1000.0 / m_tt, m_tt, 2.2 * m_tt);
            io_wr(16'h00C4, 8'h2A);
            fast_reads(16'h00C5, 16, 8'h5C, m_tt); m_bad_o = fr_bad; m_unst_o = fr_unst; m_lat_o = fr_lat;
            fast_reads(16'h00C4, 16, 8'h00, m_tt); m_bad_o = m_bad_o + fr_bad; m_unst_o = m_unst_o + fr_unst; if (fr_lat > m_lat_o) m_lat_o = fr_lat;
            fast_reads(16'h00C0, 16, 8'h06, m_tt); m_bad = fr_bad; m_unst = fr_unst; m_lat_y = fr_lat;
            y_window(18'h05000, 16);
            y_w(8'h07, 8'h20); io_wr(16'h00C0, 8'h0F);
            io_rd_fast(16'h00C1, m_tt); io_rd_fast(16'h00C1, m_tt);
            for (m_k = 0; m_k < 16; m_k = m_k + 1) begin
                io_rd_fast(16'h00C1, m_tt);
                if (!rd_driven || rdv !== y_pat(8'h3A, m_k)) m_bad = m_bad + 1;
                if (!fast_stable) m_unst = m_unst + 1;
                if (fast_lat > m_lat_y) m_lat_y = fast_lat;
            end
            y_w(8'h07, 8'h01);
            $display("         OPL4 C4h/C5h: %0d mal, %0d inestables, quieto a %0.1f ns | Y8950 C0h/C1h: %0d mal, %0d inestables, quieto a %0.1f ns",
                     m_bad_o, m_unst_o, m_lat_o, m_bad, m_unst, m_lat_y);
            ok(m_bad == 0, "  Y8950: todas las lecturas rapidas devuelven el dato correcto");
            ok(m_lat_y <= m_lat_o + 5.0, "  Y8950: dato quieto a la vez que el del OPL4 (+-5 ns)");
            // escrituras rapidas con /WR de 2,2 T
            io_wr_fast(16'h00C0, 8'h09, m_tt, 2.2 * m_tt); io_wr_fast(16'h00C1, 8'hA0 + m_i[7:0], m_tt, 2.2 * m_tt);
            ok(`YY.u_adpcm.start_addr[10:3] === 8'hA0 + m_i[7:0], "  Y8950: OUT rapidos a C0h/C1h llegan al registro 09h");
            io_wr_fast(16'h00C0, 8'hA0, m_tt, 2.2 * m_tt); io_wr_fast(16'h00C1, 8'h40 + m_i[7:0], m_tt, 2.2 * m_tt);
            ok(`YY.jt_din === 8'h40 + m_i[7:0] && `YY.jt_a0 === 1'b1, "  Y8950: el dato del OUT rapido llega a jtopl");
            io_wr_fast(16'h00C4, 8'h30 + m_i[7:0], m_tt, 2.2 * m_tt);
            ok(fpga.u_top.u_wt.u_core.u_opl4fm.sel_reg_b0 === 8'h30 + m_i[7:0], "  OPL4: OUT rapido a C4h");
        end
        cnt_report("contadores de strobes = ciclos del banco tras el barrido de turbo (ni de mas ni de menos)");

        // ---- M2. pulsos /WR cortos: anchura minima que funciona, Y8950 frente a OPL4 ----
        m_minw_y = 9999; m_minw_o = 9999;
        for (m_w = 300; m_w >= 20; m_w = m_w - 20) begin
            m_v = m_w[7:0] ^ 8'h5A;
            io_wr(16'h00C0, 8'h00); io_wr(16'h00C4, 8'h00);
            io_wr_fast(16'h00C0, m_v, 279.365, m_w);
            io_wr_fast(16'h00C4, m_v, 279.365, m_w);
            #200;
            m_ok_y = (`YY.u_adpcm.reg_sel === m_v);
            m_ok_o = (fpga.u_top.u_wt.u_core.u_opl4fm.sel_reg_b0 === m_v);
            if (m_ok_y) m_minw_y = m_w;
            if (m_ok_o) m_minw_o = m_w;
            $display("         /WR = %0d ns: Y8950 %0s, OPL4 %0s", m_w, m_ok_y ? "ok" : "PERDIDA", m_ok_o ? "ok" : "PERDIDA");
        end
        $display("         anchura minima que escribe: Y8950 %0d ns, OPL4 %0d ns", m_minw_y, m_minw_o);
        ok(m_minw_y <= m_minw_o, "un /WR corto que vale para el OPL4 vale tambien para el Y8950");
        // dato soltado en el mismo instante en que sube /WR (sin tiempo de hold)
        io_wr(16'h00C0, 8'h00);
        #(279.365) a = 16'h00C0; d_out = 8'hC3; d_oe = 1'b1;
        #(1.3 * 279.365) iorq_n = 1'b0; wr_n = 1'b0;
        #(2.2 * 279.365) wr_n = 1'b1; iorq_n = 1'b1; d_out = 8'h00;   // otro dato al instante
        #(0.3 * 279.365) d_oe = 1'b0;
        #1000;
        ok(`YY.u_adpcm.reg_sel === 8'hC3, "OUT con el dato cambiando justo al subir /WR: el Y8950 se queda con el bueno");
        ok(`YY.jt_din === 8'hC3, "  y jtopl tambien");
        cnt_clear;

        // ---- M3. ruido de bus: nada que no sea IN C1h avanza el puntero de la RAM del ADPCM ----
        y_window(18'h05000, 16);
        y_w(8'h07, 8'h20); io_wr(16'h00C0, 8'h0F);
        io_rd(16'h00C1); io_rd(16'h00C1);
        m_nb = 0;
        for (m_k = 0; m_k < 3; m_k = m_k + 1) begin io_rd(16'h00C1); if (rdv !== y_pat(8'h3A, m_k)) m_nb = m_nb + 1; end
        m_ptr0 = `YY.u_adpcm.ptr; m_d0 = `YY.u_adpcm.data_dout;
        // INTA (M1 + IORQ) sobre 00C1h, con /RD a 0 (peor caso) y sin /RD
        drive_seen = 1'b0;
        @(posedge clk358); #100 a = 16'h00C1; m1_n = 1'b0;
        repeat (2) @(posedge clk358); #75 iorq_n = 1'b0; rd_n = 1'b0;
        repeat (2) @(posedge clk358); #90 iorq_n = 1'b1; rd_n = 1'b1; m1_n = 1'b1;
        repeat (2) @(posedge clk358);
        @(posedge clk358); #100 a = 16'h00C0; m1_n = 1'b0;
        repeat (2) @(posedge clk358); #75 iorq_n = 1'b0;
        repeat (2) @(posedge clk358); #90 iorq_n = 1'b1; m1_n = 1'b1;
        repeat (2) @(posedge clk358);
        ok(!drive_seen, "INTA (M1 + IORQ) sobre C1h/C0h: el Y8950 no contesta");
        // lectura y escritura de MEMORIA en 00C1h, busqueda de opcode en 00C1h, refresco con R = C1h
        @(posedge clk358); #100 a = 16'h00C1; sltsl_n = 1'b0;
        @(negedge clk358); #80 mreq_n = 1'b0; rd_n = 1'b0;
        repeat (2) @(posedge clk358); #90 mreq_n = 1'b1; rd_n = 1'b1; sltsl_n = 1'b1;
        @(posedge clk358); #100 a = 16'h80C1; d_out = 8'h55; d_oe = 1'b1;
        @(negedge clk358); #80 mreq_n = 1'b0; @(negedge clk358) wr_n = 1'b0;
        repeat (2) @(posedge clk358); #90 mreq_n = 1'b1; wr_n = 1'b1; #20 d_oe = 1'b0;
        m1_fetch(16'h00C1, 8'h00);
        @(posedge clk358); #100 a = 16'h12C1; rfsh_n = 1'b0;
        @(negedge clk358); #80 mreq_n = 1'b0; @(posedge clk358); @(negedge clk358); #80 mreq_n = 1'b1;
        @(posedge clk358); #80 rfsh_n = 1'b1;
        // otros puertos
        io_rd(16'h00C0); io_rd(16'h00C2); io_rd(16'h00C3); io_rd(16'h00C4); io_rd(16'h007E); io_rd(16'hC1C0);
        io_rd(16'h0041); io_rd(16'hC100);
        m_rsel = `YY.u_adpcm.reg_sel;
        io_wr(16'h00C2, 8'h04); io_wr(16'h00C3, 8'h80); io_wr(16'hC1C4, 8'h20); io_wr(16'hC100, 8'h33);
        ok(`YY.u_adpcm.ptr === m_ptr0 && `YY.u_adpcm.data_dout === m_d0,
           "ruido (INTA, memoria, M1, refresco, otros puertos): el puntero de la RAM del ADPCM no se mueve");
        ok(`YY.u_adpcm.reg_sel === m_rsel && m_rsel === 8'h0F, "  y OUT a C2h/C3h/otros no toca el registro seleccionado del Y8950");
        for (m_k = 3; m_k < 8; m_k = m_k + 1) begin io_rd(16'h00C1); if (rdv !== y_pat(8'h3A, m_k)) m_nb = m_nb + 1; end
        // lecturas C1h seguidas a 10,74 MHz (INIR): una por IN
        for (m_k = 8; m_k < 16; m_k = m_k + 1) begin io_rd_fast(16'h00C1, 93.122); if (rdv !== y_pat(8'h3A, m_k)) m_nb = m_nb + 1; end
        ok(m_nb == 0, "  la secuencia de la RAM sigue donde estaba (bytes 0-15 en orden, con ruido en medio)");
        y_w(8'h07, 8'h01);
        cnt_report("contadores de strobes = ciclos C0h/C1h del banco (el ruido no genera ninguno)");

        // ---- M4. /INT: OPL3 y Y8950 en AND, en los dos ordenes ----
        for (m_i = 0; m_i < 2; m_i = m_i + 1) begin
            fm_w(0, 8'h02, 8'hFF); fm_w(0, 8'h04, 8'h01);
            y_w(8'h02, 8'hFF);     y_w(8'h04, 8'h39);
            #400_000;
            ok(fpga.u_top.u_wt.u_core.opl4fm_int_n === 1'b0 && fpga.u_top.u_wt.u_core.y8950_int_n === 1'b0 && s_int_n === 1'b0,
               "las dos IRQ activas: /INT abajo");
            if (m_i == 0) begin
                fm_w(0, 8'h04, 8'h00); fm_w(0, 8'h04, 8'h80);
                #600_000;
                ok(fpga.u_top.u_wt.u_core.opl4fm_int_n === 1'b1 && s_int_n === 1'b0, "  OPL3 atendida, Y8950 no: /INT sigue abajo");
                y_w(8'h04, 8'h78); io_wr(16'h00C1, 8'h80);
            end
            else begin
                y_w(8'h04, 8'h78); io_wr(16'h00C1, 8'h80);
                #600_000;
                ok(fpga.u_top.u_wt.u_core.y8950_int_n === 1'b1 && s_int_n === 1'b0, "  Y8950 atendida, OPL3 no: /INT sigue abajo");
                fm_w(0, 8'h04, 8'h00); fm_w(0, 8'h04, 8'h80);
            end
            #600_000;
            ok(s_int_n === 1'b1, "  las dos atendidas: /INT se suelta");
        end

        // ---- M5. /RESET del MSX a mitad de operacion ----
        y_upload(18'h06000, 64, 8'h19);
        y_window(18'h06000, 64);
        y_w(8'h10, 8'h00); y_w(8'h11, 8'hC0); y_w(8'h12, 8'hFF);
        y_w(8'h20, 8'h21); y_w(8'h23, 8'h21); y_w(8'h40, 8'h3F); y_w(8'h43, 8'h00);
        y_w(8'h60, 8'hF0); y_w(8'h63, 8'hF0); y_w(8'h80, 8'h00); y_w(8'h83, 8'h00);   // RR = 0: no calla solo
        y_w(8'hC0, 8'h01); y_w(8'hA0, 8'h44); y_w(8'hB0, 8'h32);
        y_w(8'h02, 8'hFF); y_w(8'h04, 8'h29);                     // T1 y EOS visibles
        y_w(8'h07, 8'hB0);                                         // START + RAM + REPEAT
        audio_clear; #400_000;
        ok(s_int_n === 1'b0 && yad_max > 200 && yfm_max > 1000, "antes del /RESET: ADPCM y FM sonando, /INT abajo");   // patron 19h: el ADPCM llega a ~650
        // /RESET a mitad de un IN C1h
        @(posedge clk358); #110 a = 16'h00C1;
        @(posedge clk358); #75 iorq_n = 1'b0; #10 rd_n = 1'b0;
        #150 reset_n = 1'b0;
        #200 iorq_n = 1'b1; rd_n = 1'b1;
        #100_000 reset_n = 1'b1;
        #50_000;
        ok(s_int_n === 1'b1, "tras el /RESET: /INT suelto");
        io_rd(16'h00C0);
        ok(rdv === 8'h06, "  status 06h");
        audio_clear; #300_000;
        $display("         tras el /RESET: ADPCM max=%0d min=%0d, FM Y8950 max=%0d min=%0d", yad_max, yad_min, yfm_max, yfm_min);
        ok(yad_max == 0 && yad_min == 0, "  el ADPCM calla");
        ok(yfm_max < 64 && yfm_min > -64, "  el FM del Y8950 calla");
        // /RESET a mitad de un OUT C1h de subida a la RAM
        y_window(18'h07000, 16);
        y_w(8'h07, 8'h60); io_wr(16'h00C0, 8'h0F);
        for (m_k = 0; m_k < 7; m_k = m_k + 1) io_wr(16'h00C1, y_pat(8'h2C, m_k));
        @(posedge clk358); #110 a = 16'h00C1;
        @(negedge clk358); #100 d_out = 8'hEE; d_oe = 1'b1;
        @(posedge clk358); #75 iorq_n = 1'b0; #5 wr_n = 1'b0;
        #60 reset_n = 1'b0;
        #300 wr_n = 1'b1; iorq_n = 1'b1; #60 d_oe = 1'b0;
        #100_000 reset_n = 1'b1;
        #50_000;
        ok(fpga.u_top.u_wt.u_core.u_bridge.st === 3'd0 && `YY.u_ram.g_sdram.st === 2'd0 && `YY.u_ram.g_sdram.r_req === 1'b0,
           "tras el /RESET a mitad de una subida: puente y adpcm_sdram en reposo");
        y_readback(18'h05000, 16, 8'h3A, m_nb);
        ok(m_nb == 0, "  la RAM del ADPCM conserva lo anterior (05000h)");
        y_upload(18'h08000, 16, 8'h4D);
        y_readback(18'h08000, 16, 8'h4D, m_nb);
        ok(m_nb == 0, "  y se puede subir y releer de nuevo (08000h)");
        ok(`YY.mem_diag === 8'h00, "  mem_diag = 00h");
        ok(fpga.u_top.u_wt.u_core.sd_timeout === 1'b0, "  el watchdog del puente no salto");

        $display("== M-fin. salud ==");
        ok(bad_drive == 0, "la placa nunca condujo D0-D7 fuera de una lectura suya");
        ok(bad_busdir == 0, "/BUSDIR acompaño siempre a la conduccion del bus");
        ok(setup_viol == 0, "ningun dato cambio en la ventana de muestreo del Z80 (ciclos a 3,58 MHz)");
        fin;
        end
`endif

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
        // El indicador usa la marca de agua alta: un sample al ultimo byte
        // equivale a los 2 MiB completos y debe encender los 28 segmentos.
        wv_w(8'h03, 8'h3F); wv_w(8'h04, 8'hFF); wv_w(8'h05, 8'hFF);
        wv_w(8'h06, 8'h69);
        wv_w(8'h03, 8'h3F); wv_w(8'h04, 8'hFF); wv_w(8'h05, 8'hFF);
        wv_r(8'h06);     ok(rdv === 8'h69, "RAM[3FFFFF] = 69h");
        #2_000;
        ok(gray22bin(fpga.u_top.u_wt.sample_used_gray) == 22'h200000,
           "marca de agua de sample RAM = 2 MiB");
        if (HDMI) begin
            #2_000;
            ok(fpga.u_top.u_av.sample_level_s1 == 5'd28,
               "HDMI: la barra SAMPLE RAM llega al 100 por ciento");
        end
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

`ifdef WITH_Y8950
        // ==============================================================
        $display("== L. MSX-Audio (Y8950) en C0h-C1h ==");
`ifdef WITH_VU_Y8950
        fase_L = 1'b1;
`endif
        // la nota FM del OPL4 de la fase I quedo en KEY OFF con RR = 0 (suelta
        // infinita) y en esta simulacion sigue sonando tras los /RESET de J y J2
        // (unos 4100 en el FM R): se le da RR = 15 ya, antes de L1, para que lo
        // que L3 (ADPCM) y L4 (FM del Y8950) miden en el altavoz sea solo del
        // Y8950. L3 y L4 comprueban que el OPL4 esta callado (maximo y minimo):
        // con la envolvente al minimo el OPL3 aun deja unos pocos LSB (medido: R
        // entre -9 y 0, unos -71 dB), asi que "callado" es |x| <= 16 (OPL4_RESTO)
        fm_w(0, 8'h80, 8'h0F); fm_w(0, 8'h83, 8'h0F); fm_w(0, 8'hB0, 8'h12);
        io_rd(16'h00C0);
        ok(rdv === 8'h06, "tras el /RESET del MSX: status 06h");
        io_rd(16'h5AC0);
        ok(rdv === 8'h06, "con A8-A15 a basura sigue decodificando por A0-A7");

        // ---- L1. timer 1 -> /INT del slot ----
        ok(s_int_n === 1'b1, "/INT en reposo");
        y_w(8'h02, 8'hFF);                          // timer 1: un tick (80 us)
        y_w(8'h04, 8'h39);                          // T2/EOS/BUF_RDY tapados, T1 visible, ST1
        int_seen = 1'b0;
        fork : espera_int_y
            begin wait (s_int_n === 1'b0); int_seen = 1'b1; disable espera_int_y; end
            begin #1_500_000; disable espera_int_y; end
        join
        ok(int_seen, "timer 1 del Y8950 -> /INT del slot baja");
        ok(fpga.u_top.u_wt.u_core.opl4fm_int_n === 1'b1, "  y es el Y8950, no el OPL3");
        io_rd(16'h00C0);
        ok((rdv & 8'hC0) == 8'hC0, "status: IRQ + FT1");
        $display("         status = %02x", rdv);
        y_w(8'h04, 8'h78);                          // todo tapado, timers parados
        io_wr(16'h00C1, 8'h80);                     // y despues el reset de flags
        #600_000;
        ok(s_int_n === 1'b1, "/INT se suelta tras parar el timer y resetear los flags");
        io_rd(16'h00C0);
        ok(rdv === 8'h06, "  y el status vuelve a 06h");

        // ---- L2. RAM de muestras: por encima de 32 KB, al final de 256 KB, sin alias ----
        n_wr0 = sdram.n_wr;
        y_upload(18'h0A000, 8, 8'h11);              // por encima de 32 KB
        y_upload(18'h02000, 8, 8'h22);              // 0A000h modulo 32 KB
        y_upload(18'h3FFF8, 8, 8'h33);              // los ultimos 8 bytes de 256 KB
        y_upload(18'h1FFF8, 8, 8'h44);              // 3FFF8h modulo 128 KB
        ok(sdram.n_wr - n_wr0 == 32, "32 bytes subidos: 32 escrituras en la SDRAM");
        nb = 0;
        for (i = 0; i < 8; i = i + 1) begin
            if (sd_adpcm(18'h0A000 + i) !== y_pat(8'h11, i)) nb = nb + 1;
            if (sd_adpcm(18'h3FFF8 + i) !== y_pat(8'h33, i)) nb = nb + 1;
        end
        ok(nb == 0, "  y estan en el banco 2 de la SDRAM (bus_address[22] = 1), en su sitio");
        y_readback(18'h0A000, 8, 8'h11, nb);
        ok(nb == 0, "relectura por C1h (dos lecturas de relleno) en 0A000h, por encima de 32 KB");
        y_readback(18'h3FFF8, 8, 8'h33, nb);
        ok(nb == 0, "relectura de los ultimos 8 bytes de los 256 KB (3FFF8h)");
        y_readback(18'h02000, 8, 8'h22, nb);
        y_readback(18'h1FFF8, 8, 8'h44, nb2);
        ok(nb == 0 && nb2 == 0, "sin alias: 02000h y 1FFF8h guardan lo suyo");

        // ---- L3. una muestra corta: ADPCM distinto de cero en la salida y EOS ----
        y_window(18'h24000, 64);
        y_w(8'h07, 8'h60); io_wr(16'h00C0, 8'h0F);
        for (i = 0; i < 64; i = i + 1) io_wr(16'h00C1, i[2] ? 8'hFF : 8'h77);
        y_w(8'h07, 8'h01);
        y_w(8'h10, 8'h00); y_w(8'h11, 8'hC0);      // delta-N: 37 kHz de nibbles
        y_w(8'h12, 8'hFF);                          // volumen a tope
        y_w(8'h04, 8'h78); io_wr(16'h00C1, 8'h80); // la subida deja EOS a 1: se borra
        y_w(8'h04, 8'h68);                          // solo EOS visible
        io_rd(16'h00C0);
        ok(rdv === 8'h06 && s_int_n === 1'b1, "antes de reproducir: status 06h, sin IRQ");
        audio_clear;
        y_w(8'h07, 8'hA0);                          // START, desde la RAM
        polls = 0; st_y = 8'h00;
        while (!st_y[4] && polls < 60) begin #200_000; io_rd(16'h00C0); st_y = rdv; polls = polls + 1; end
        $display("         ADPCM: max=%0d min=%0d | altavoz: max=%0d min=%0d (esperado (ADPCM>>>3) x5: %0d / %0d) | status = %02x tras %0d sondeos",
                 yad_max, yad_min, spk_max, spk_min, 5*(yad_max>>>3), 5*(yad_min>>>3), st_y, polls);
        $display("         mientras: FM del OPL4 L %0d..%0d R %0d..%0d | PCM %0d..%0d | FM del Y8950 %0d..%0d",
                 fml_min, fml_max, fmr_min, fmr_max, pcm_min, pcm_max, yfm_min, yfm_max);
        ok(yad_max > 1000 && yad_min < -1000, "la muestra suena: salida ADPCM distinta de cero");
        ok(fml_max <= OPL4_RESTO && fml_min >= -OPL4_RESTO && fmr_max <= OPL4_RESTO && fmr_min >= -OPL4_RESTO &&
           pcm_max == 0 && pcm_min == 0 && yfm_max == 0 && yfm_min == 0,
           "  (el OPL4 y el FM del Y8950 estan callados: el altavoz es solo el ADPCM)");
        // en el altavoz, el ADPCM con su peso en la mezcla, (ADPCM>>>3) x5 (por
        // debajo del codo del limitador, sin tocar); el I2S toma una muestra por
        // trama y puede no coger el pico exacto: entre 3/4 de lo esperado y lo
        // esperado
        ok(spk_max > 500 && spk_min < -500 &&
           spk_max >= (5*(yad_max>>>3))*3/4 && spk_max <= 5*(yad_max>>>3) + OPL4_RESTO &&
           spk_min <= (5*(yad_min>>>3))*3/4 && spk_min >= 5*(yad_min>>>3) - OPL4_RESTO,
           "  y llega al altavoz por I2S, con su nivel en la mezcla ((ADPCM>>>3) x5)");
        ok(st_y[4] && st_y[7], "al final de la muestra sube EOS (con IRQ)");
        ok(s_int_n === 1'b0, "  y la IRQ de EOS llega al /INT del slot");
        y_w(8'h07, 8'h01);
        y_w(8'h04, 8'h78); io_wr(16'h00C1, 8'h80);
        #600_000;
        ok(s_int_n === 1'b1, "/INT suelto otra vez");

        // ---- L4. una nota FM del Y8950 en el altavoz ----
        // (el OPL4 se callo al empezar la fase L)
        audio_clear; #200_000;
        ok(fml_max <= OPL4_RESTO && fml_min >= -OPL4_RESTO && fmr_max <= OPL4_RESTO && fmr_min >= -OPL4_RESTO,
           "(el FM del OPL4 esta callado)");
        y_w(8'h20, 8'h21); y_w(8'h23, 8'h21);      // MULT = 1, envolvente sostenida
        y_w(8'h40, 8'h3F); y_w(8'h43, 8'h00);      // moduladora muda, portadora a tope
        y_w(8'h60, 8'hF0); y_w(8'h63, 8'hF0);      // AR = 15
        y_w(8'h80, 8'h0F); y_w(8'h83, 8'h0F);      // RR = 15
        y_w(8'hC0, 8'h01);                          // aditivo
        y_w(8'hA0, 8'h44); y_w(8'hB0, 8'h32);      // KEY ON
        #1_000_000; audio_clear; #3_000_000;
        $display("         FM del Y8950: max=%0d min=%0d | altavoz: max=%0d min=%0d | FM del OPL4: L %0d..%0d R %0d..%0d",
                 yfm_max, yfm_min, spk_max, spk_min, fml_min, fml_max, fmr_min, fmr_max);
        ok(yfm_max > 1000 && yfm_min < -1000, "nota FM del Y8950 (jtopl2)");
        ok(spk_max > 1000 && spk_min < -1000, "  se oye en el altavoz (I2S decodificado en el modelo de la placa)");
        ok(fml_max <= OPL4_RESTO && fml_min >= -OPL4_RESTO && fmr_max <= OPL4_RESTO && fmr_min >= -OPL4_RESTO,
           "  sin tocar el FM del OPL4");
        y_w(8'hB0, 8'h12);                          // KEY OFF
        #2_000_000; audio_clear; #400_000;
        ok(spk_max < 200 && spk_min > -200, "KEY OFF: silencio");

        // ---- L4b. escrituras del FM en cada fase del reloj del Z80 ----
        // El reloj del MSX (315/88 MHz) y los 108 MHz de la FPGA vuelven a la
        // misma fase cada 35 ciclos del Z80 (1056 de 108 MHz), y el escaner del
        // bus multiplexado (9 estados a 108 MHz) cada 105 (3168 = 352 vueltas).
        // Una escritura que dependa de donde cae /WR frente a la FPGA (como el FM
        // con el ciclo de bus entero, que al final puede ver el bus ya suelto)
        // va bien en unas fases y mal en otras: la nota de L4 prueba solo las que
        // le tocan. Aqui se escribe el registro A1h (F-num del canal 1, sin nota)
        // una vez en cada una de las 105 fases y se mira lo que jtopl se ha
        // quedado (indice y dato).
        nb = 0;
        for (i = 0; i < 105; i = i + 1) begin
            while (z80_cyc % 105 != i) @(posedge clk358);
            y_w(8'hA1, 8'h11 + i[7:0] * 8'h05);       // nunca FFh con i < 150
            if (fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_fm.u_base.u_mmr.selreg   !== 8'hA1 ||
                fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_fm.u_base.u_mmr.din_copy !== 8'h11 + i[7:0] * 8'h05) begin
                nb = nb + 1;
                $display("         fase %0d: jtopl tiene registro %02x = %02x (escrito A1h = %02x)", i,
                         fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_fm.u_base.u_mmr.selreg,
                         fpga.u_top.u_wt.u_core.g_y8950.u_y8950.u_fm.u_base.u_mmr.din_copy, 8'h11 + i[7:0] * 8'h05);
            end
        end
        $display("         %0d de 105 escrituras con el indice o el dato equivocado", nb);
        ok(nb == 0, "FM del Y8950: OUT en las 105 fases Z80/FPGA, todas con su indice y su dato");
        y_w(8'hA1, 8'h00);

        // ---- L5. el Y8950 y el OPL4 no se pisan ----
        fm_w(0, 8'h2A, 8'h6B); fm_w(1, 8'h2B, 8'h94);
        wv_w(8'h50, 8'h3C);
        y_w(8'h2A, 8'h11); y_w(8'h2B, 8'h22); y_w(8'h50, 8'h33); y_w(8'h05, 8'h00);
        io_wr(16'h00C4, 8'h2A); io_rd(16'h00C5); nb = (rdv !== 8'h6B);
        io_wr(16'h00C6, 8'h2B); io_rd(16'h00C7); nb = nb + (rdv !== 8'h94);
        wv_r(8'h50);                                 nb = nb + (rdv !== 8'h3C);
        io_rd(16'h00C4);                             nb = nb + ((rdv & 8'hE0) != 8'h00);
        ok(nb == 0, "escribir en el Y8950 (registros 2Ah, 2Bh, 50h, 05h) no cambia el OPL4");
        y_upload(18'h0A000, 8, 8'h55);
        fm_w(0, 8'h07, 8'h01); fm_w(0, 8'h0F, 8'hAA); fm_w(0, 8'h08, 8'h01); fm_w(1, 8'h07, 8'h60);
        wv_w(8'h02, 8'h01);                         // RAM de muestras del OPL4 en 20A000h
        wv_w(8'h03, 8'h20); wv_w(8'h04, 8'hA0); wv_w(8'h05, 8'h00);
        wv_w(8'h06, 8'hE1); io_wr(16'h007F, 8'hE2); io_wr(16'h007F, 8'hE3); io_wr(16'h007F, 8'hE4);
        wv_w(8'h03, 8'h20); wv_w(8'h04, 8'hA0); wv_w(8'h05, 8'h00);
        wv_r(8'h06); nb2 = (rdv !== 8'hE1);
        wv_w(8'h02, 8'h00);
        io_rd(16'h00C0);
        ok(rdv === 8'h06, "escribir en el OPL4 (registros 07h, 0Fh, 08h...) no toca el status del Y8950");
        y_readback(18'h0A000, 8, 8'h55, nb);
        ok(nb == 0 && nb2 == 0, "  ni su RAM de muestras: 0A000h del ADPCM y 20A000h del OPL4 guardan lo suyo");
        ok(sd_adpcm(18'h0A000) === y_pat(8'h55, 0) &&
           sdram.mem[{2'b01, 3'b000, 16'h2800}][7:0] === 8'hE1,
           "  (el ADPCM en el banco 2, la RAM del OPL4 en el banco 1)");

        // ---- L6. con los tiempos de un Z80 en turbo (7,16 y 10,74 MHz) ----
        // Las lecturas del Y8950 tienen que aguantar lo mismo que las del OPL4:
        // se leen 16 veces C4h (status del OPL4), C5h (registro del OPL4), C0h
        // y C1h (RAM del ADPCM) y se compara el peor retardo desde /IORQ hasta
        // que el dato queda quieto. Ademas, escrituras con /WR de 2,2 T.
        fm_w(0, 8'h2A, 8'h5C);
        for (i = 0; i < 2; i = i + 1) begin
            tt = (i == 0) ? 139.682 : 93.122;
            $display("         -- turbo a %0.2f MHz: T = %0.1f ns, dato muestreado %0.0f ns tras /IORQ, /WR de %0.0f ns --",
                     1000.0 / tt, tt, 2.2 * tt, 2.2 * tt);
            n_fw0 = fast_wait;
            io_wr(16'h00C4, 8'h2A);
            fast_reads(16'h00C5, 16, 8'h5C, tt); nb = fr_bad; f = fr_lat; polls = fr_unst;
            $display("         C5h (registro del OPL4): %0d mal, %0d inestables, dato quieto como muy tarde %0.1f ns tras /IORQ", fr_bad, fr_unst, fr_lat);
            fast_reads(16'h00C4, 16, 8'h00, tt); nb = nb + fr_bad; polls = polls + fr_unst; if (fr_lat > f) f = fr_lat;
            $display("         C4h (status del OPL4):   %0d mal, %0d inestables, %0.1f ns", fr_bad, fr_unst, fr_lat);
            fast_reads(16'h00C0, 16, 8'h06, tt); nb2 = fr_bad; n_ok = fr_unst; t_ref0 = fr_lat;
            $display("         C0h (status del Y8950):  %0d mal, %0d inestables, %0.1f ns", fr_bad, fr_unst, fr_lat);
            y_upload(18'h31000 + 18'h100 * i, 16, 8'h66 + i[7:0]);
            y_window(18'h31000 + 18'h100 * i, 16);
            y_w(8'h07, 8'h20); io_wr(16'h00C0, 8'h0F);
            io_rd_fast(16'h00C1, tt); io_rd_fast(16'h00C1, tt);
            for (k = 0; k < 16; k = k + 1) begin
                io_rd_fast(16'h00C1, tt);
                if (!rd_driven || rdv !== y_pat(8'h66 + i[7:0], k)) nb2 = nb2 + 1;
                if (!fast_stable) n_ok = n_ok + 1;
                if (fast_lat > t_ref0) t_ref0 = fast_lat;
            end
            y_w(8'h07, 8'h01);
            $display("         C0h + C1h (RAM del ADPCM): %0d mal, %0d inestables, %0.1f ns", nb2, n_ok, t_ref0);
            if (i == 0) begin
                ok(nb == 0 && polls == 0, "  7,16 MHz: el OPL4 se lee bien");
                ok(nb2 == 0 && n_ok == 0, "  7,16 MHz: el Y8950 tambien (C0h y C1h, sin un dato inestable)");
            end
            // (la fase del barrido del bus multiplexado, 83 ns, mueve el retardo de
            //  cada lectura: se admite la mitad de un ciclo de 108 MHz)
            ok(t_ref0 <= f + 5.0, "  el dato del Y8950 queda quieto a la vez que el del OPL4 (+-5 ns)");
            ok(nb2 <= nb, "  y no lee mal mas veces que el OPL4");
            if (n_ok + polls > 0)
                $display("         (al limite para los dos: %0d lecturas del OPL4 y %0d del Y8950 cambian dentro de los 50 ns de preparacion)", polls, n_ok);
            ok(fast_wait == n_fw0, "  ninguna de estas lecturas pide /WAIT");
            // escrituras rapidas: OPL4 y subida al ADPCM
            io_wr_fast(16'h00C4, 8'h2B, tt, 2.2 * tt); io_wr_fast(16'h00C5, 8'hA0 + i[7:0], tt, 2.2 * tt);
            io_wr(16'h00C4, 8'h2B); io_rd(16'h00C5);
            ok(rdv === 8'hA0 + i[7:0], "  OPL4: registro escrito con OUT rapidos");
            y_window(18'h31800 + 18'h100 * i, 16);
            io_wr_fast(16'h00C0, 8'h07, tt, 2.2 * tt); io_wr_fast(16'h00C1, 8'h60, tt, 2.2 * tt);
            io_wr_fast(16'h00C0, 8'h0F, tt, 2.2 * tt);
            for (k = 0; k < 16; k = k + 1)
                io_wr_fast(16'h00C1, y_pat(8'h77 + i[7:0], k), tt, 2.2 * tt);
            y_w(8'h07, 8'h01);
            y_readback(18'h31800 + 18'h100 * i, 16, 8'h77 + i[7:0], nb);
            ok(nb == 0, "  Y8950: 16 bytes subidos al ADPCM con OUT rapidos, ninguno perdido");
        end
        ok(fpga.u_top.u_wt.u_core.g_y8950.u_y8950.mem_diag === 8'h00,
           "el ADPCM no perdio ninguna escritura ni disparo su watchdog (mem_diag = 00h)");
`endif

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
`ifdef WITH_VU_Y8950
        vu_y8950_checks;
`endif
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

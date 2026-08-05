// ============================================================================
// tb_loader.v — verifica el loader del YRW801 contra un modelo de flash EN RAMPA.
//
// EL FALLO QUE BUSCA (auditoria 2026-08-05): el loader antiguo muestreaba
// `flash_data_ready` como NIVEL, pero flash_rw lo limpia UN CICLO DESPUES de
// ver `rd` y `dout` conserva mientras tanto el byte ANTERIOR. Resultado: la
// imagen aterrizaba DUPLICADA (cada byte escrito dos veces => solo 1 MB de los
// 2 leidos) o DESPLAZADA +1, segun la latencia — y como la latencia depende del
// place&route, el modo de fallo cambiaba de build en build. Con la YRW801
// descolocada, TODA la wavetable suena a basura.
//
// El modelo de flash reproduce el handshake de flash_rw (busy sube al aceptar
// `rd`, baja con el dato listo; data_ready se solapa) con LATENCIA PARAMETRIZABLE,
// y sirve el byte k = k (rampa) para que cualquier duplicado o salto se detecte.
//
// Comprobaciones:
//   1. Se escriben EXACTAMENTE WAVE_SIZE bytes.
//   2. Las direcciones son estrictamente incrementales 0,1,2,... sin repetir.
//   3. El dato escrito en la direccion k es EXACTAMENTE el byte k de la flash.
//   4. wl_done sube al final y wl_error queda a 0.
// Se repite a varias latencias porque el bug original dependia de ellas.
// ============================================================================
`timescale 1ns/1ps

module tb_loader;

    // tamaño reducido para que la simulacion sea rapida; la logica es la misma
    localparam [22:0] TEST_SIZE  = 23'd4096;
    localparam [23:0] TEST_BASE  = 24'h200000;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;              // 100 MHz nominal (da igual)

    reg start = 0;

    // ---- interfaz con el loader ----
    wire [23:0] flash_addr;
    wire        flash_rd, flash_terminate;
    reg  [7:0]  flash_dout;
    reg         flash_data_ready, flash_busy;

    wire        wl_req_toggle, wl_we;
    wire [21:0] wl_addr;
    wire [7:0]  wl_wdata;
    reg         wl_done_toggle;
    wire        wl_done, wl_error;
    wire [2:0]  wl_dbg_state;

    yrw801_loader #(
        .FLASH_BASE(TEST_BASE), .WAVE_SIZE(TEST_SIZE),
        .TIMEOUT(24'd200000), .MAX_RETRIES(3)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .flash_addr(flash_addr), .flash_rd(flash_rd), .flash_dout(flash_dout),
        .flash_data_ready(flash_data_ready), .flash_busy(flash_busy),
        .flash_terminate(flash_terminate),
        .wl_req_toggle(wl_req_toggle), .wl_we(wl_we), .wl_addr(wl_addr),
        .wl_wdata(wl_wdata), .wl_done_toggle(wl_done_toggle),
        .wl_done(wl_done), .wl_error(wl_error), .wl_dbg_state(wl_dbg_state)
    );

    // ------------------------------------------------------------------
    //  Modelo de flash: rampa (byte k = k), con la MISMA forma de handshake
    //  que flash_rw (busy y data_ready se solapan; dout conserva el byte
    //  anterior hasta que el nuevo esta listo).
    // ------------------------------------------------------------------
    integer FLASH_LAT = 8;
    integer stream_idx = 0;
    integer f_state = 0, f_cnt = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flash_busy <= 0; flash_data_ready <= 0; flash_dout <= 8'hEE;
            f_state <= 0; f_cnt <= 0; stream_idx <= 0;
        end
        else begin
            case (f_state)
            0: begin                                   // ocioso
                flash_busy <= 0;
                if (flash_terminate) stream_idx <= 0;  // cierra la lectura
                if (flash_rd) begin
                    flash_busy       <= 1;
                    flash_data_ready <= 0;             // se limpia UN ciclo DESPUES
                    f_cnt   <= 0;
                    f_state <= 1;
                end
            end
            1: begin                                   // sirviendo el byte
                if (f_cnt >= FLASH_LAT) begin
                    flash_dout       <= stream_idx[7:0];   // rampa
                    flash_data_ready <= 1;
                    flash_busy       <= 0;
                    stream_idx       <= stream_idx + 1;
                    f_state          <= 0;
                end
                else f_cnt <= f_cnt + 1;
            end
            endcase
        end
    end

    // ------------------------------------------------------------------
    //  Modelo de wave_sdram (lado host): responde con done tras N ciclos
    // ------------------------------------------------------------------
    integer HOST_LAT = 6;
    reg  prev_req = 0;
    integer h_cnt = 0, h_busy = 0;

    // memoria de comprobacion
    reg [7:0] mem [0:TEST_SIZE-1];
    reg       written [0:TEST_SIZE-1];
    integer   writes = 0, seq_errors = 0, data_errors = 0, dup_errors = 0;
    integer   expect_addr = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wl_done_toggle <= 0; prev_req <= 0; h_busy <= 0; h_cnt <= 0;
        end
        else begin
            prev_req <= wl_req_toggle;
            if (wl_req_toggle != prev_req && !h_busy) begin
                h_busy <= 1; h_cnt <= 0;
            end
            else if (h_busy) begin
                if (h_cnt >= HOST_LAT) begin
                    h_busy <= 0;
                    // registrar la escritura
                    if (wl_we) begin
                        if (wl_addr >= TEST_SIZE) begin
                            $display("  [FAIL] escritura FUERA DE RANGO: addr=%0d", wl_addr);
                            seq_errors = seq_errors + 1;
                        end
                        else begin
                            if (written[wl_addr]) begin
                                dup_errors = dup_errors + 1;
                                if (dup_errors < 4)
                                    $display("  [FAIL] direccion REPETIDA %0d (byte duplicado)", wl_addr);
                            end
                            if (wl_addr !== expect_addr[21:0]) begin
                                seq_errors = seq_errors + 1;
                                if (seq_errors < 4)
                                    $display("  [FAIL] salto de direccion: esperaba %0d, llego %0d",
                                             expect_addr, wl_addr);
                            end
                            else expect_addr = expect_addr + 1;
                            mem[wl_addr]     = wl_wdata;
                            written[wl_addr] = 1;
                            writes = writes + 1;
                        end
                    end
                    wl_done_toggle <= ~wl_done_toggle;
                end
                else h_cnt <= h_cnt + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    integer i, total_fail = 0;

    task run_case;
        input integer flat;
        input integer hlat;
        begin
            // reset completo
            rst_n = 0; start = 0;
            FLASH_LAT = flat; HOST_LAT = hlat;
            writes = 0; seq_errors = 0; data_errors = 0; dup_errors = 0;
            expect_addr = 0;
            for (i = 0; i < TEST_SIZE; i = i + 1) begin written[i] = 0; mem[i] = 8'hxx; end
            repeat (5) @(posedge clk);
            rst_n = 1;
            repeat (5) @(posedge clk);
            start = 1;

            // esperar a que termine
            wait (wl_done === 1'b1);
            repeat (20) @(posedge clk);

            // comprobar contenido: mem[k] debe ser el byte k de la rampa
            for (i = 0; i < TEST_SIZE; i = i + 1) begin
                if (mem[i] !== i[7:0]) begin
                    data_errors = data_errors + 1;
                    if (data_errors < 4)
                        $display("  [FAIL] contenido en %0d: 0x%02x, esperado 0x%02x",
                                 i, mem[i], i[7:0]);
                end
            end

            $display("  flash_lat=%0d host_lat=%0d -> escrituras=%0d  saltos=%0d  duplicados=%0d  contenido_mal=%0d  wl_error=%b",
                     flat, hlat, writes, seq_errors, dup_errors, data_errors, wl_error);
            if (writes !== TEST_SIZE || seq_errors || dup_errors || data_errors || wl_error) begin
                $display("     ^^ FALLO");
                total_fail = total_fail + 1;
            end
        end
    endtask

    initial begin
        $display("== loader YRW801: integridad de la copia flash -> SDRAM ==");
        $display("   (%0d bytes, rampa byte k = k)", TEST_SIZE);
        run_case(3,  3);
        run_case(8,  6);
        run_case(20, 8);
        run_case(4,  40);
        run_case(40, 4);
        $display("== casos fallidos: %0d ==", total_fail);
        if (total_fail == 0) $display("RESULTADO: PASS - copia integra a todas las latencias");
        else                 $display("RESULTADO: FAIL");
        $finish;
    end

    initial begin
        #500_000_000;
        $display("RESULTADO: FAIL (timeout global)");
        $finish;
    end

endmodule

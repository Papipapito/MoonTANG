// ============================================================================
// tb_loader_real.v — loader YRW801 + flash_rw REAL + modelo de chip SPI.
//
// Este es el banco con poder de deteccion: el modelo "de interfaz" que escribi
// primero NO reproducia el peligro (limpiaba data_ready demasiado pronto) y el
// control negativo con el bug reintroducido PASABA — un test sin poder es peor
// que no tener test. Aqui se usa el flash_rw.v de verdad, que es quien tiene la
// temporizacion real de `data_ready` (se limpia un ciclo DESPUES de ver `rd`,
// con `dout` conservando el byte anterior): justo la trampa del bug original.
//
// Comprobaciones: numero exacto de bytes, direcciones estrictamente crecientes
// sin repetir, y contenido == rampa (byte de la direccion A vale A[7:0]).
// ============================================================================
`timescale 1ns/1ps

module tb_loader_real;

    localparam [22:0] TEST_SIZE = 23'd512;      // suficiente y rapido (SPI es lento)
    localparam [23:0] TEST_BASE = 24'h200000;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg start = 0;

    // ---- loader <-> flash_rw ----
    wire [23:0] fl_addr;
    wire        fl_rd, fl_terminate;
    wire [7:0]  fl_dout;
    wire        fl_data_ready, fl_busy;

    // ---- flash_rw <-> chip ----
    wire SCLK, CS, MOSI, MISO;

    // ---- loader <-> wave_sdram (modelo) ----
    wire        wl_req_toggle, wl_we;
    wire [21:0] wl_addr;
    wire [7:0]  wl_wdata;
    reg         wl_done_toggle = 0;
    wire        wl_done, wl_error, wl_sum_ok;
    // suma de la rampa de 512 bytes desde 0x200000: dos veces 0..255 = FF00h
    // (+SUM_DELTA para el control negativo: con otra suma esperada, sum_ok = 0)
    parameter [31:0] SUM_DELTA = 32'd0;

    yrw801_loader #(
        .FLASH_BASE(TEST_BASE), .WAVE_SIZE(TEST_SIZE),
        .TIMEOUT(24'd3000000), .MAX_RETRIES(3),
        .EXPECTED_SUM(32'h0000FF00 + SUM_DELTA)
    ) u_loader (
        .clk(clk), .rst_n(rst_n), .start(start),
        .flash_addr(fl_addr), .flash_rd(fl_rd), .flash_dout(fl_dout),
        .flash_data_ready(fl_data_ready), .flash_busy(fl_busy),
        .flash_terminate(fl_terminate),
        .wl_req_toggle(wl_req_toggle), .wl_we(wl_we), .wl_addr(wl_addr),
        .wl_wdata(wl_wdata), .wl_done_toggle(wl_done_toggle),
        .wl_done(wl_done), .wl_error(wl_error), .wl_sum_ok(wl_sum_ok), .wl_dbg_state()
    );

    // flash_rw REAL (STARTUP_WAIT reducido para no eternizar la sim)
    flash #(.STARTUP_WAIT(32'd200)) u_flash (
        .clk(clk), .reset_n(rst_n),
        .SCLK(SCLK), .CS(CS), .MISO(MISO), .MOSI(MOSI),
        .addr(fl_addr), .rd(fl_rd), .dout(fl_dout),
        .data_ready(fl_data_ready), .busy(fl_busy), .terminate(fl_terminate),
        .write_enable(1'b0), .write_din(8'd0), .write_addr(24'd0),
        .write_busy(), .write_terminate(1'b0), .write_counter()
    );

    spi_flash_model u_chip (.CS(CS), .SCLK(SCLK), .MOSI(MOSI), .MISO(MISO));

    // ------------------------------------------------------------------
    //  Modelo del puerto host de wave_sdram + comprobador
    // ------------------------------------------------------------------
    integer HOST_LAT = 6;
    reg     prev_req = 0;
    integer h_cnt = 0, h_busy = 0;

    reg [7:0] mem [0:TEST_SIZE-1];
    reg       written [0:TEST_SIZE-1];
    integer   writes = 0, seq_err = 0, dup_err = 0, data_err = 0;
    integer   expect_addr = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wl_done_toggle <= 0; prev_req <= 0; h_busy <= 0; h_cnt <= 0;
        end
        else begin
            prev_req <= wl_req_toggle;
            if (wl_req_toggle != prev_req && !h_busy) begin h_busy <= 1; h_cnt <= 0; end
            else if (h_busy) begin
                if (h_cnt >= HOST_LAT) begin
                    h_busy <= 0;
                    if (wl_we && wl_addr < TEST_SIZE) begin
                        if (written[wl_addr]) begin
                            dup_err = dup_err + 1;
                            if (dup_err < 4) $display("  [FAIL] direccion REPETIDA %0d", wl_addr);
                        end
                        if (wl_addr !== expect_addr[21:0]) begin
                            seq_err = seq_err + 1;
                            if (seq_err < 4)
                                $display("  [FAIL] salto: esperaba %0d, llego %0d", expect_addr, wl_addr);
                        end
                        else expect_addr = expect_addr + 1;
                        mem[wl_addr] = wl_wdata; written[wl_addr] = 1;
                        writes = writes + 1;
                    end
                    wl_done_toggle <= ~wl_done_toggle;
                end
                else h_cnt <= h_cnt + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    integer i;
    initial begin
        for (i = 0; i < TEST_SIZE; i = i + 1) begin written[i] = 0; mem[i] = 8'hxx; end
        $display("== loader + flash_rw REAL + chip SPI (rampa) ==");
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (400) @(posedge clk);     // arranque de flash_rw
        start = 1;

        wait (wl_done === 1'b1);
        repeat (50) @(posedge clk);

        // contenido esperado: mem[k] == (TEST_BASE + k)[7:0]
        for (i = 0; i < TEST_SIZE; i = i + 1) begin
            if (mem[i] !== ((TEST_BASE + i) & 8'hFF)) begin
                data_err = data_err + 1;
                if (data_err < 6)
                    $display("  [FAIL] contenido en %0d: 0x%02x, esperado 0x%02x",
                             i, mem[i], (TEST_BASE + i) & 8'hFF);
            end
        end

        $display("  escrituras=%0d/%0d  saltos=%0d  duplicados=%0d  contenido_mal=%0d  wl_error=%b  suma_ok=%b",
                 writes, TEST_SIZE, seq_err, dup_err, data_err, wl_error, wl_sum_ok);
        if (writes == TEST_SIZE && seq_err == 0 && dup_err == 0 && data_err == 0 && !wl_error
            && wl_sum_ok === (SUM_DELTA == 0))
            $display("RESULTADO: PASS - copia integra contra el flash_rw real");
        else
            $display("RESULTADO: FAIL");
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("RESULTADO: FAIL (timeout)");
        $finish;
    end

endmodule

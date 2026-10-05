// ============================================================================
// sdram_model.v — modelo de la SDRAM SDR embebida del GW2AR-18 (64 Mbit,
//                 2M x 32: 4 bancos x 2048 filas x 256 columnas).
//
// Lo justo para comprobar un controlador: MRS (latencia CAS), ACT, READ/WRITE
// de una posicion con auto-precarga, PRE, REF, mascaras DQM en escritura.
// La memoria nace a X: leer algo que no se ha escrito se ve.
//
// VENTANA DE DATO VALIDO. El RTL no tiene retardos de E/S, asi que aqui se
// suman los del camino real, todos referidos al flanco de reloj que ve el RTL:
//     dato valido  desde  flanco(N+CL-1) + T_VALID
//                  hasta  flanco(N+CL)   + T_HOLD
//   T_VALID = salida del reloj de la FPGA al chip + tAC + entrada a la FPGA
//   T_HOLD  = salida del reloj (min)             + tOH + entrada (min)
// Fuera de la ventana el bus se conduce a X: un controlador que capture
// demasiado pronto o demasiado tarde lee X y el banco lo canta.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module sdram_model #(
    parameter real T_VALID = 10.5,      // 3.0 (reloj) + 6.0 (tAC, CL=2) + 1.5 (entrada)
    parameter real T_HOLD  = 5.5        // 2.0 (reloj) + 2.5 (tOH)       + 1.0 (entrada)
) (
    input  wire        clk,
    input  wire        cke,
    input  wire        cs_n, ras_n, cas_n, we_n,
    input  wire [10:0] addr,
    input  wire [1:0]  ba,
    input  wire [3:0]  dqm,
    inout  wire [31:0] dq
);
    reg [31:0] mem [0:2097151];

    reg [10:0] row [0:3];
    reg [3:0]  row_open = 4'b0000;
    reg [2:0]  cl = 3'd0;               // 0 = sin programar
    reg        mrs_done = 1'b0;

    integer n_act = 0, n_rd = 0, n_wr = 0, n_ref = 0, n_err = 0;
    realtime t_act [0:3];
    realtime t_last_ref_or_act = 0;

    wire [3:0] cmd = {cs_n, ras_n, cas_n, we_n};
    localparam [3:0] C_MRS = 4'b0000, C_REF = 4'b0001, C_PRE = 4'b0010, C_ACT = 4'b0011,
                     C_WR  = 4'b0100, C_RD  = 4'b0101, C_NOP = 4'b0111;

    // tuberia de lectura
    reg        rd_p1 = 1'b0, rd_p2 = 1'b0;
    reg [31:0] rd_d1 = 32'd0, rd_d2 = 32'd0;
    reg [31:0] dq_out = 32'd0;
    reg [1:0]  dq_mode = 2'd0;          // 0 = Z, 1 = X (transicion), 2 = dato
    assign dq = (dq_mode == 2'd2) ? dq_out : (dq_mode == 2'd1) ? 32'hxxxxxxxx : 32'hzzzzzzzz;

    wire [20:0] widx = {ba, row[ba], addr[7:0]};
    integer b;
    reg [31:0] wtmp;

    task err(input [255:0] what);
        begin
            n_err = n_err + 1;
            $display("  [SDRAM %0t] ERROR: %0s", $time, what);
        end
    endtask

    always @(posedge clk) if (cke) begin
        rd_p2 <= rd_p1; rd_d2 <= rd_d1;
        rd_p1 <= 1'b0;
        case (cmd)
        C_MRS: begin
            cl <= addr[6:4]; mrs_done <= 1'b1;
            if (addr[6:4] != 3'd2 && addr[6:4] != 3'd3) err("latencia CAS no soportada");
            if (row_open != 4'b0000) err("MRS con filas abiertas");
        end
        C_REF: begin
            n_ref = n_ref + 1;
            if (row_open != 4'b0000) err("REFRESH con filas abiertas");
            if ($realtime - t_last_ref_or_act < 55.0 && t_last_ref_or_act != 0) err("tRC violado antes de REF");
            t_last_ref_or_act = $realtime;
        end
        C_PRE: begin
            if (addr[10]) row_open <= 4'b0000;
            else          row_open[ba] <= 1'b0;
        end
        C_ACT: begin
            n_act = n_act + 1;
            if (row_open[ba]) err("ACT sobre un banco con fila abierta");
            if (!mrs_done) err("ACT antes del MRS");
            if ($realtime - t_last_ref_or_act < 55.0 && t_last_ref_or_act != 0) err("tRC violado antes de ACT");
            row[ba] <= addr; row_open[ba] <= 1'b1;
            t_act[ba] = $realtime; t_last_ref_or_act = $realtime;
        end
        C_RD: begin
            n_rd = n_rd + 1;
            if (!row_open[ba]) err("READ sin fila abierta");
            if ($realtime - t_act[ba] < 15.0) err("tRCD violado en READ");
            if (dqm != 4'b0000) err("READ con DQM activo");
            rd_p1 <= 1'b1; rd_d1 <= mem[widx];
            if (addr[10]) row_open[ba] <= 1'b0;         // auto-precarga
        end
        C_WR: begin
            n_wr = n_wr + 1;
            if (!row_open[ba]) err("WRITE sin fila abierta");
            if ($realtime - t_act[ba] < 15.0) err("tRCD violado en WRITE");
            wtmp = mem[widx];
            for (b = 0; b < 4; b = b + 1)
                if (!dqm[b]) begin
                    if (^dq[b*8 +: 8] === 1'bx) err("WRITE con dato X/Z en el bus");
                    wtmp[b*8 +: 8] = dq[b*8 +: 8];
                end
            mem[widx] = wtmp;
            if (addr[10]) row_open[ba] <= 1'b0;
        end
        default: ;
        endcase
    end

    // ---- conduccion del bus de datos con la ventana real ----
    wire out_now = (cl == 3'd2) ? rd_p1 : rd_p2;
    wire [31:0] out_dat = (cl == 3'd2) ? rd_d1 : rd_d2;
    reg  out_q = 1'b0;
    always @(posedge clk) if (cke) begin
        out_q <= out_now;
        if (out_now) begin
            // el dato anterior (si lo hubo) se mantiene T_HOLD; despues X hasta T_VALID
            dq_mode <= #(T_HOLD) 2'd1;
            dq_out  <= #(T_VALID) out_dat;
            dq_mode <= #(T_VALID) 2'd2;
        end
        else if (out_q) begin
            dq_mode <= #(T_HOLD) 2'd1;          // deja de ser valido
            dq_mode <= #(T_HOLD + 2.0) 2'd0;    // y suelta el bus
        end
    end
endmodule

`default_nettype wire

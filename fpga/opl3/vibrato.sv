/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: vibrato.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 13 Oct 2014
#
#   DESCRIPTION:
#   Prepare the phase increment for the NCO (calc multiplier and vibrato)
#
#   CHANGE HISTORY:
#   13 Oct 2026    MSXimus (Papipapito)
#       Arreglado para casar con Nuked-OPL3 / YMF262: el LFO avanzaba en cada
#       operador (36 veces mas rapido), la mitad negativa entraba sin signo y
#       el desplazamiento se sumaba despues del bloque. Ahora el LFO avanza
#       una vez por muestra, vib_val_p0 sale CON SIGNO (combinacional en p0) y
#       calc_phase_inc lo suma al F-NUMBER, antes del bloque y del multiplicador.
#
#   13 Oct 2014    Greg Taylor
#       Initial version
#
#   Copyright (C) 2014 Greg Taylor <gtaylor@sonic.net>
#
#   This file is part of OPL3 FPGA.
#
#   OPL3 FPGA is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   OPL3 FPGA is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public License
#   along with OPL3 FPGA.  If not, see <http://www.gnu.org/licenses/>.
#
#   Original Java Code:
#   Copyright (C) 2008 Robson Cozendey <robson@cozendey.com>
#
#   Original C++ Code:
#   Copyright (C) 2012  Steffen Ohrendorf <steffen.ohrendorf@gmx.de>
#
#   Some code based on forum posts in:
#   http://forums.submarine.org.uk/phpBB/viewforum.php?f=9,
#   Copyright (C) 2010-2013 by carbon14 and opl3
#
#******************************************************************************/
`timescale 1ns / 1ps
`default_nettype none

module vibrato
    import opl3_pkg::*;
(
    input wire clk,
    input wire sample_clk_en,
    input wire [BANK_NUM_WIDTH-1:0] bank_num,
    input wire [OP_NUM_WIDTH-1:0] op_num,
    input wire [REG_FNUM_WIDTH-1:0] fnum,
    input wire dvb,
    output logic signed [VIB_VAL_WIDTH:0] vib_val_p0 // con signo: a sumar al fnum
);
    localparam VIBRATO_INDEX_WIDTH = 13;

    logic [VIBRATO_INDEX_WIDTH-1:0] vibrato_index_p0 = 0;
    logic [VIB_VAL_WIDTH-1:0] delta0_p0;
    logic [VIB_VAL_WIDTH-1:0] delta1_p0;
    logic [VIB_VAL_WIDTH-1:0] delta2_p0;

    /*
     * Low-Frequency Oscillator (LFO)
     * 6.07Hz (Sample Freq/2**13)
     * Avanza UNA vez por muestra, en el ultimo operador (banco 1, operador
     * 17): los 36 operadores de una muestra leen en p0 el mismo indice (el
     * tremolo avanza en el 0/0 porque lee su indice una etapa despues).
     * Antes avanzaba con cada operador: 36 x fs/2**13 = 217.7 Hz.
     */
    always_ff @(posedge clk)
        if (sample_clk_en && bank_num == NUM_BANKS - 1 && op_num == NUM_OPERATORS_PER_BANK - 1)
            vibrato_index_p0 <= vibrato_index_p0 + 1;

    /*
     * Escalera del canon (Nuked-OPL3, vibpos = indice >> 10): para vibpos
     * 0..7 el desplazamiento es 0, +h, +f, +h, 0, -h, -f, -h con f = fnum[9:7]
     * y h = f/2. Con DVB=0 todo a la mitad.
     */
    always_comb delta0_p0 = fnum >> 7;
    always_comb
        if (((vibrato_index_p0 >> 10) & 3) == 0)
            delta1_p0 = 0;
        else if (((vibrato_index_p0 >> 10) & 1) != 0)
            delta1_p0 = delta0_p0 >> 1;
        else
            delta1_p0 = delta0_p0;
    always_comb delta2_p0 = !dvb ? delta1_p0 >> 1 : delta1_p0;

    always_comb
        vib_val_p0 = ((vibrato_index_p0 >> 10) & 4) != 0 ? -signed'({1'b0, delta2_p0}) : signed'({1'b0, delta2_p0});
endmodule
`default_nettype wire
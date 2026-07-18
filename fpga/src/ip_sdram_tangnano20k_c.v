//
// ip_sdram.v
//
//	Copyright (C) 2025 Takayuki Hara
//
//	�{�\�t�g�E�F�A����і{�\�t�g�E�F�A�Ɋ�Â��č쐬���ꂽ�h�����́A�ȉ��̏�����
//	�������ꍇ�Ɍ���A�ĔЕz����юg�p��������܂��B
//
//	1.�\�[�X�R�[�h�`���ōĔЕz����ꍇ�A��L�̒��쌠�\���A�{�����ꗗ�A����щ��L
//	  �Ɛӏ��������̂܂܂̌`�ŕێ����邱�ƁB
//	2.�o�C�i���`���ōĔЕz����ꍇ�A�Еz���ɕt���̃h�L�������g���̎����ɁA��L��
//	  ���쌠�\���A�{�����ꗗ�A����щ��L�Ɛӏ������܂߂邱�ƁB
//	3.���ʂɂ�鎖�O�̋��Ȃ��ɁA�{�\�t�g�E�F�A��̔��A����я��ƓI�Ȑ��i�⊈��
//	  �Ɏg�p���Ȃ����ƁB
//
//	�{�\�t�g�E�F�A�́A���쌠�҂ɂ���āu����̂܂܁v�񋟂���Ă��܂��B���쌠�҂́A
//	����ړI�ւ̓K�����̕ۏ؁A���i���̕ۏ؁A�܂�����Ɍ��肳��Ȃ��A�����Ȃ閾��
//	�I�������͈ÖقȕۏؐӔC�������܂���B���쌠�҂́A���R�̂�������킸�A���Q
//	�����̌�����������킸�A���ӔC�̍������_��ł��邩���i�ӔC�ł��邩�i�ߎ�
//	���̑��́j�s�@�s�ׂł��邩���킸�A���ɂ��̂悤�ȑ��Q����������\����m��
//	����Ă����Ƃ��Ă��A�{�\�t�g�E�F�A�̎g�p�ɂ���Ĕ��������i��֕i�܂��͑�p�T
//	�[�r�X�̒��B�A�g�p�̑r���A�f�[�^�̑r���A���v�̑r���A�Ɩ��̒��f���܂߁A�܂���
//	��Ɍ��肳��Ȃ��j���ڑ��Q�A�Ԑڑ��Q�A�����I�ȑ��Q�A���ʑ��Q�A�����I���Q�A��
//	���͌��ʑ��Q�ɂ��āA��ؐӔC�𕉂�Ȃ����̂Ƃ��܂��B
//
//	Note that above Japanese version license is the formal document.
//	The following translation is only for reference.
//
//	Redistribution and use of this software or any derivative works,
//	are permitted provided that the following conditions are met:
//
//	1. Redistributions of source code must retain the above copyright
//	   notice, this list of conditions and the following disclaimer.
//	2. Redistributions in binary form must reproduce the above
//	   copyright notice, this list of conditions and the following
//	   disclaimer in the documentation and/or other materials
//	   provided with the distribution.
//	3. Redistributions may not be sold, nor may they be used in a
//	   commercial product or activity without specific prior written
//	   permission.
//
//	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//	"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//	LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//	FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//	COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//	INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
//	LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
//	ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//	POSSIBILITY OF SUCH DAMAGE.
//
//-----------------------------------------------------------------------------

module ip_sdram #(
	parameter		FREQ = 85_909_080	//	Hz
) (
	input				reset_n,
	input				clk,				//	85.90908MHz
	input				clk_sdram,
	output				sdram_init_busy,

	input	[22:2]		bus_address,
	input				bus_valid,
	input				bus_write,
	input				bus_refresh,
	input	[31:0]		bus_wdata,
	input	[3:0]		bus_wdata_mask,
	output	[31:0]		bus_rdata,
	output				bus_rdata_en,
	output				bus_ready,		// MoonTANG add: 1 = controller idle/ready for a new bus_valid

	// SDRAM ports
	output				O_sdram_clk,
	output				O_sdram_cke,
	output				O_sdram_cs_n,		// chip select
	output				O_sdram_ras_n,		// row address select
	output				O_sdram_cas_n,		// columns address select
	output				O_sdram_wen_n,		// write enable
	inout	[31:0]		IO_sdram_dq,		// 32 bit bidirectional data bus
	output	[10:0]		O_sdram_addr,		// 11 bit multiplexed address bus
	output	[ 1:0]		O_sdram_ba,			// two banks
	output	[ 3:0]		O_sdram_dqm			// data mask
);
	//	SDRAM commands
	localparam	[3:0]	c_sdr_command_mode_register_set		= 4'b0000;
	localparam	[3:0]	c_sdr_command_refresh				= 4'b0001;
	localparam	[3:0]	c_sdr_command_precharge_all			= 4'b0010;
	localparam	[3:0]	c_sdr_command_activate				= 4'b0011;
	localparam	[3:0]	c_sdr_command_write					= 4'b0100;
	localparam	[3:0]	c_sdr_command_read					= 4'b0101;
	localparam	[3:0]	c_sdr_command_burst_stop			= 4'b0110;
	localparam	[3:0]	c_sdr_command_no_operation			= 4'b0111;
	localparam	[3:0]	c_sdr_command_deselect				= 4'b1111;

	//	State value
	localparam	[4:0]	c_init_state_begin_first_wait		= 5'd0;
	localparam	[4:0]	c_init_state_first_wait				= 5'd1;
	localparam	[4:0]	c_init_state_send_precharge_all		= 5'd2;
	localparam	[4:0]	c_init_state_wait_precharge_all		= 5'd3;
	localparam	[4:0]	c_init_state_send_refresh_all1		= 5'd4;
	localparam	[4:0]	c_init_state_wait_refresh_all1		= 5'd5;
	localparam	[4:0]	c_init_state_send_refresh_all2		= 5'd6;
	localparam	[4:0]	c_init_state_wait_refresh_all2		= 5'd7;
	localparam	[4:0]	c_init_state_send_mode_register_set	= 5'd8;
	localparam	[4:0]	c_init_state_wait_mode_register_set	= 5'd9;
	localparam	[4:0]	c_main_state_ready					= 5'd10;
	localparam	[4:0]	c_main_state_activate				= 5'd11;
	localparam	[4:0]	c_main_state_nop1					= 5'd12;
	localparam	[4:0]	c_main_state_nop2					= 5'd13;
	localparam	[4:0]	c_main_state_read_or_write			= 5'd14;
	localparam	[4:0]	c_main_state_nop3					= 5'd15;
	localparam	[4:0]	c_main_state_data_fetch				= 5'd16;
	localparam	[4:0]	c_main_state_finish					= 5'd17;
	localparam	[4:0]	c_main_state_nop4					= 5'd18;
	localparam	[4:0]	c_main_state_nop5					= 5'd19;
	localparam	[4:0]	c_main_state_nop6					= 5'd20;
	localparam	[4:0]	c_main_state_nop7					= 5'd21;
	localparam	[4:0]	c_main_state_finish2				= 5'd22;

	localparam CLOCK_TIME		= 1_000_000_000 / FREQ;		// nsec
	localparam TIMER_COUNT		= 300_000 / CLOCK_TIME;		// clock
	localparam TIMER_BITS		= $clog2(TIMER_COUNT + 1);
	localparam REFRESH_COUNT	= 15_000 / CLOCK_TIME;		// clock
	localparam REFRESH_BITS		= $clog2(REFRESH_COUNT + 1);
	localparam REFRESH_NONE		= 10_000 / CLOCK_TIME;		// clock

	reg		[ 4:0]				ff_main_state;
	reg		[TIMER_BITS-1:0]	ff_main_timer;
	wire						w_end_of_main_timer;

	reg							ff_sdr_ready;
	reg							ff_do_main_state;
	reg							ff_do_refresh;

	reg		[ 3:0]				ff_sdr_command;
	reg		[ 1:0]				ff_sdr_bank;
	reg		[10:0]				ff_sdr_address;
	reg		[31:0]				ff_sdr_write_data;
	reg		[ 3:0]				ff_sdr_dq_mask;
	reg		[31:0]				ff_sdr_read_data;
	reg							ff_sdr_read_data_en;
	reg							ff_do_command;
	reg							ff_write;
	reg		[31:0]				ff_wdata;
	reg		[ 3:0]				ff_wdata_mask;
	reg		[ 1:0]				ff_bank;
	reg		[10:0]				ff_row_address;
	reg		[ 7:0]				ff_col_address;
	wire						w_busy;
	reg							ff_initial_finish;

	// --------------------------------------------------------------------
	//	Request latch
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_do_command	<= 1'b0;
			ff_write		<= 1'b0;
			ff_wdata		<= 32'd0;
			ff_wdata_mask	<= 4'd0;
			ff_bank			<= 2'd0;
			ff_row_address	<= 11'd0;
			ff_col_address	<= 8'd0;
			ff_do_refresh	<= 1'b0;
		end
		else if( (ff_main_state == c_main_state_ready) && (bus_valid || bus_refresh) ) begin
			ff_do_command	<= 1'b1;
			ff_do_refresh	<= bus_refresh;
			ff_write		<= bus_write;
			ff_wdata		<= bus_wdata;
			ff_wdata_mask	<= bus_wdata_mask;
			ff_bank			<= bus_address[22:21];
			ff_row_address	<= bus_address[20:10];
			ff_col_address	<= bus_address[9:2];
		end
		else if( (ff_main_state == c_main_state_finish) || (ff_main_state == c_main_state_finish2) ) begin
			ff_do_command	<= 1'b0;
			ff_do_refresh	<= 1'b0;
			ff_write		<= 1'b0;
		end
	end

	// --------------------------------------------------------------------
	//	Main State
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_main_state		<= c_init_state_begin_first_wait;
			ff_do_main_state	<= 1'b0;
		end
		else begin
			case( ff_main_state )
			c_init_state_begin_first_wait:
				ff_main_state	<= c_init_state_first_wait;
			c_init_state_send_precharge_all:
				ff_main_state	<= c_init_state_wait_precharge_all;
			c_init_state_send_refresh_all1:
				ff_main_state	<= c_init_state_wait_refresh_all1;
			c_init_state_send_refresh_all2:
				ff_main_state	<= c_init_state_wait_refresh_all2;
			c_init_state_send_mode_register_set:
				ff_main_state	<= c_init_state_wait_mode_register_set;
			// ----------------------------------------------------------------
			c_main_state_ready:
				if( bus_valid || bus_refresh ) begin
					ff_main_state		<= c_main_state_activate;
				end
			c_main_state_activate:
				begin
					ff_main_state		<= c_main_state_nop1;
					ff_do_main_state	<= 1'b1;
				end
			c_main_state_read_or_write:
				begin
					if( ff_do_refresh ) begin
						ff_main_state		<= c_main_state_nop4;
					end
					else begin
						ff_main_state		<= c_main_state_nop3;
					end
				end
			c_main_state_finish, c_main_state_finish2:
				begin
					ff_main_state		<= c_main_state_ready;
					ff_do_main_state	<= 1'b0;
				end
			default:
				if( (!ff_sdr_ready && w_end_of_main_timer) || (ff_sdr_ready && ff_do_main_state) ) begin
					ff_main_state	<= ff_main_state + 5'd1;
				end
				else begin
					//	hold
				end
			endcase
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_initial_finish	<= 1'b0;
		end
		else if( w_end_of_main_timer && ff_main_state == c_init_state_first_wait ) begin
			ff_initial_finish	<= 1'b1;
		end
	end

	assign w_busy			= ff_do_command;
	assign sdram_init_busy	= !ff_sdr_ready;

	// --------------------------------------------------------------------
	//	Sub State
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_sdr_ready	<= 1'b0;
		end
		else if( (ff_main_state == c_init_state_wait_mode_register_set) && w_end_of_main_timer ) begin
			ff_sdr_ready	<= 1'b1;
		end
		else begin
			//	hold
		end
	end

	// --------------------------------------------------------------------
	//	Main Timer
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		case( ff_main_state )
		c_init_state_begin_first_wait:
			ff_main_timer	<= TIMER_COUNT;		//	initial time
		c_init_state_send_precharge_all:
			ff_main_timer	<= 'd5;
		c_init_state_send_refresh_all1:
			ff_main_timer	<= 'd15;
		c_init_state_send_refresh_all2:
			ff_main_timer	<= 'd15;
		c_init_state_send_mode_register_set:
			ff_main_timer	<= 'd2;
		default:
			//	ff_main_timer is decrement counter.
			if( !w_end_of_main_timer ) begin
				ff_main_timer	<= ff_main_timer - 'd1;
			end
			else begin
				//	hold
			end
		endcase
	end

	assign w_end_of_main_timer	= (ff_main_timer == 'd0) ? 1'b1 : 1'b0;

	// --------------------------------------------------------------------
	//	SDRAM Command Signal
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_sdr_command		<= c_sdr_command_no_operation;
			ff_sdr_dq_mask		<= 4'b1111;
		end
		else begin
			case( ff_main_state )
			c_init_state_send_precharge_all:
				begin
					ff_sdr_command		<= c_sdr_command_precharge_all;
					ff_sdr_dq_mask		<= 4'b1111;
				end
			c_init_state_send_refresh_all1, c_init_state_send_refresh_all2:
				begin
					ff_sdr_command		<= c_sdr_command_refresh;
					ff_sdr_dq_mask		<= 4'b0000;
				end
			c_init_state_send_mode_register_set:
				begin
					ff_sdr_command		<= c_sdr_command_mode_register_set;
					ff_sdr_dq_mask		<= 4'b1111;
				end
			default:
				if( ff_sdr_ready ) begin
					case( ff_main_state )
					c_main_state_activate:
						if( ff_do_refresh ) begin
//							$display( "do_refresh: precharge_all" );
							ff_sdr_command		<= c_sdr_command_precharge_all;
							ff_sdr_dq_mask		<= 4'b0000;
						end
						else begin
//							$display( "activate address %X", ff_row_address );
							ff_sdr_command		<= c_sdr_command_activate;
							ff_sdr_dq_mask		<= 4'b1111;
						end
					c_main_state_read_or_write:
						if( ff_do_refresh ) begin
							ff_sdr_command		<= c_sdr_command_refresh;
							ff_sdr_dq_mask		<= 4'b0000;
						end
						else if( ff_write ) begin
							ff_sdr_command		<= c_sdr_command_write;
							ff_sdr_dq_mask		<= ff_wdata_mask;
						end
						else begin
							ff_sdr_command		<= c_sdr_command_read;
							ff_sdr_dq_mask		<= 4'b0000;
						end
					default:
						begin
							ff_sdr_command		<= c_sdr_command_no_operation;
							ff_sdr_dq_mask		<= 4'b1111;
						end
					endcase
				end
				else begin
					ff_sdr_command		<= c_sdr_command_no_operation;
					ff_sdr_dq_mask		<= 4'b1111;
				end
			endcase
		end
	end

	// --------------------------------------------------------------------
	//	 bit12  11     10   9   8    7    6     5     4     3   2    1    0
	//	[Bank1][Bank0][RSV][WB][OP1][OP0][CAS2][CAS1][CAS0][BT][BL2][BL1][BL0] : mode
	//	
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_sdr_bank <= 2'd0;
			ff_sdr_address <= 11'd0;
		end
		else if( !ff_sdr_ready ) begin
			case( ff_main_state )
			c_init_state_send_precharge_all:
				begin
					ff_sdr_bank <= 2'd0;			// Ignore
					ff_sdr_address <= { 
						1'b1,						//	All banks
						10'd0						//	Ignore
					};
				end
			default:
				begin
					ff_sdr_bank <= 2'd0;			//	Ignore
					ff_sdr_address <= { 
						1'b0,						//	Reserved
						1'b1,						//	Write burst mode  0: Programmed Burst Length, 1: Single Location Access
						2'b00,						//	Operation mode    00: Standard Operation, others: Reserved
						3'b010,						//	CAS Latency       010: 2cyc, 011: 3cyc, others: Reserved
						1'b0,						//	Burst type        0: Sequential Access, 1: Interleave Access
						3'b000						//	Burst length      000: 1, 001: 2, 010: 4, 011: 8, 111: full page (Sequential Access only), others: Reserved
					};
				end
			endcase
		end
		else begin
			case( ff_main_state )
			c_main_state_activate:
				begin
					ff_sdr_bank <= ff_bank;				// Bank
					ff_sdr_address <= ff_row_address;	// Row address
				end
			c_main_state_read_or_write:
				begin
					if( ff_do_refresh ) begin
//						$display( "do_refresh" );
						ff_sdr_bank <= 2'd0;	// Ignore
						ff_sdr_address <= { 
							1'b1,				// All banks
							10'd0				// Ignore
						};
					end
					else begin
						ff_sdr_bank <= ff_bank;
						ff_sdr_address <= { 
							1'b1,				// Enable auto precharge
							2'd0,				// 00
							ff_col_address	 	// Column address
						};
					end
				end
			default:
				begin
					//	hold
				end
			endcase
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_sdr_write_data <= 32'dz;
		end
		else if( ff_main_state == c_main_state_read_or_write ) begin
			ff_sdr_write_data <= ff_wdata;
		end
		else begin
			ff_sdr_write_data <= 32'dz;
		end
	end

	always @( posedge clk_sdram ) begin
		if( !reset_n ) begin
			ff_sdr_read_data	<= 32'd0;
		end
		else if( ff_main_state == c_main_state_finish ) begin
			ff_sdr_read_data	<= IO_sdram_dq;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_sdr_read_data_en	<= 1'b0;
		end
		else if( ff_main_state == c_main_state_finish ) begin
			ff_sdr_read_data_en	<= ~ff_write & ~ff_do_refresh;
		end
		else if( ff_sdr_read_data_en ) begin
			ff_sdr_read_data_en	<= 1'b0;
		end
	end

	assign O_sdram_clk			= clk_sdram;
	assign O_sdram_cke			= ff_initial_finish;
	assign O_sdram_cs_n			= ff_sdr_command[3];
	assign O_sdram_ras_n		= ff_sdr_command[2];
	assign O_sdram_cas_n		= ff_sdr_command[1];
	assign O_sdram_wen_n		= ff_sdr_command[0];

	assign O_sdram_dqm			= ff_sdr_dq_mask;
	assign O_sdram_ba			= ff_sdr_bank;

	assign O_sdram_addr			= ff_sdr_address;
	assign IO_sdram_dq			= ff_sdr_write_data;

	assign bus_rdata			= ff_sdr_read_data;
	assign bus_rdata_en			= ff_sdr_read_data_en;
	//	MoonTANG add: ready when the main FSM is idle in the ready state and the
	//	init sequence has finished. A client may assert bus_valid/bus_refresh
	//	only while this is high (it is deasserted for the whole transaction).
	assign bus_ready			= ff_sdr_ready & ( ff_main_state == c_main_state_ready );
endmodule

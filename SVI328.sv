//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================


// TODO
//  - Complete Keyboard Mapping
//  - Make Memory size select from OSD
//  - Select PAL/NTSC
//  - OSD Load Keyboard Map 
//  - Tape Load Graphical wave
//  - Tape Counter (bytes)

// Done
//  - Rewind on CAS load or Reset
//  - LED_Disk on Tape Load

//Core : 
//Z80 - 3,5555Mhz
//AY - z80/2 = 1,777 Mhz
//Mess :
//Z80 - 3,579545
//AY - 1,789772

`default_nettype none


module SVI328
(       
        output        LED,                                              
        output        VGA_HS,
        output        VGA_VS,
        output        AUDIO_L,
        output        AUDIO_R, 
		output [15:0]  DAC_L, 
		output [15:0]  DAC_R, 
        input         TAPE_IN,
        input         UART_RX,
        output        UART_TX,
        input         SPI_SCK,
        output        SPI_DO,
        input         SPI_DI,
        input         SPI_SS2,
        input         SPI_SS3,
        input         CONF_DATA0,
        input         CLOCK_27,
        output  [5:0] VGA_R,
        output  [5:0] VGA_G,
        output  [5:0] VGA_B,

		  output [12:0] SDRAM_A,
		  inout  [15:0] SDRAM_DQ,
		  output        SDRAM_DQML,
        output        SDRAM_DQMH,
        output        SDRAM_nWE,
        output        SDRAM_nCAS,
        output        SDRAM_nRAS,
        output        SDRAM_nCS,
        output  [1:0] SDRAM_BA,
        output        SDRAM_CLK,
        output        SDRAM_CKE
);


 
assign LED  =  svi_audio_in;




`include "build_id.v" 
parameter CONF_STR = {
	"SVI328;;",
	"F,BINROM,Load Cartridge;",
	"F,CAS,Cas File;",
`ifndef DEMISTIFY_NO_LINE_IN	
	"OF,Tape Input,File,Line;",
`endif
	"OE,Tape Audio,Off,On;",
	"TD,Tape Rewind;",
	"O79,Scanlines,Off,25%,50%,75%;",
	"O6,Border,No,Yes;",
	"O3,Joysticks swap,No,Yes;",
`ifdef DEMISTIFY_HAVE_ARM
	"T0,Reset;",
	"T1,Hard reset;",
`else
	"T0,Reset (Hold for hard reset);",
`endif
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys;
wire pll_locked;

pll pll
(
	.inclk0(CLOCK_27),
	.c0(clk_sys),
	.c1(SDRAM_CLK),
	.locked(pll_locked)
);

reg ce_10m7 = 0;
reg ce_5m3 = 0;
reg ce_21m3 = 0;
always @(posedge clk_sys) begin
	reg [2:0] div;
	
	div <= div+1'd1;
	ce_10m7 <= !div[1:0];
	ce_5m3  <= !div[2:0];
	ce_21m3 <= div[0];
end

/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [31:0] joy0, joy1;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        forced_scandoubler;
wire [21:0] gamma_bus;
wire [10:0] PS2Keys;
wire        ypbpr;

 
mist_io #(.STRLEN($size(CONF_STR)>>3),.PS2DIV(100)) mist_io
(
	.SPI_SCK   (SPI_SCK),
   .CONF_DATA0(CONF_DATA0),
   .SPI_SS2   (SPI_SS2),
   .SPI_DO    (SPI_DO),
   .SPI_DI    (SPI_DI),

   .clk_sys(clk_sys),
   .conf_str(CONF_STR),

   .buttons(buttons),
   .status(status),
   .scandoubler_disable(forced_scandoubler),
   .ypbpr     (ypbpr),
	
   .ioctl_ce(1),
   .ioctl_download(ioctl_download),
   .ioctl_index(ioctl_index),
   .ioctl_wr(ioctl_wr),
   .ioctl_addr(ioctl_addr),
   .ioctl_dout(ioctl_dout),
		
   .ps2_key(PS2Keys),
	
   .joystick_0(joy0), // HPS joy [4:0] {Fire, Up, Down, Left, Right}
   .joystick_1(joy1)

);

/////////////////  RESET  /////////////////////////

wire reset = status[0] | buttons[1] | (ioctl_download && ioctl_isROM) | in_hard_reset;

wire hard_reset = status[1];
reg [15:0] cleanup_addr = 16'd0;
reg cleanup_we;
wire in_hard_reset = |cleanup_addr;

always @(posedge clk_sys) begin
    reg hard_reset_last;
    reg ce_last;
    
    hard_reset_last <= hard_reset;
    ce_last <= ce_5m3;
    if (~hard_reset_last & hard_reset) begin
        cleanup_addr <= 16'hffff;
        cleanup_we <= 1'b1;
    end
    else if (~ce_last & ce_5m3) begin
        if (|cleanup_addr) begin
            case (cleanup_we) 
                1'b0: cleanup_we <= 1'b1;
                1'b1: begin
                    cleanup_we <= 1'b0;
                    cleanup_addr <= cleanup_addr - 1'b1;
                end
            endcase
        end
    end
end

////////////////  KeyBoard  ///////////////////////


wire [3:0] svi_row;
wire [7:0] svi_col;
sviKeyboard KeyboardSVI
(
	.clk		(clk_sys),
	.reset	(reset),
	
	.keys		(PS2Keys),
	.svi_row (svi_row),
	.svi_col (svi_col)
	
);


wire [15:0] cpu_ram_a;
wire        ram_we_n, ram_rd_n, ram_ce_n;
wire  [7:0] ram_di;
wire  [7:0] ram_do;


wire [13:0] vram_a;
wire        vram_we;
wire  [7:0] vram_di;
wire  [7:0] vram_do;

spram #(14) vram
(
	.clock(clk_sys),
	.address(vram_a),
	.wren(vram_we),
	.data(vram_do),
	.q(vram_di)
);



wire sdram_we,sdram_rd;
wire [24:0] sdram_addr;
reg  [7:0] sdram_din;
wire [15:0] sdram_q;
wire [1:0] sdram_ds;
wire ioctl_isROM = (ioctl_index[5:0]<6'd2); //Index osd File is 0 (ROM) or 1(Rom Cartridge)


assign sdram_we = (ioctl_wr && ioctl_isROM) | 
                  (isRam & ~(ram_we_n | ram_ce_n)) | 
                  (in_hard_reset & cleanup_we);

assign sdram_addr[22:0] = (ioctl_download && ioctl_isROM) ? {ioctl_index[0],ioctl_addr[15:0]} :
       in_hard_reset ? {1'b1, cleanup_addr} :
       ram_a;

assign sdram_addr[24] = 1'b0;
assign sdram_din = (ioctl_download && ioctl_isROM) ? ioctl_dout : 
    in_hard_reset ? 8'h00 :
    ram_do;

assign sdram_rd = ~(ram_rd_n | ram_ce_n);

wire sdram_req;
wire sdram_ack;
reg sdram_ack_d;
reg sdram_wren;
always @(posedge clk_sys) begin
	if(sdram_rd | sdram_we) begin
		sdram_req <= ~sdram_ack_d;
		sdram_wren <= sdram_we;
	end	else
		sdram_ack_d <= sdram_ack;
end

assign sdram_ds = {~sdram_addr[0],sdram_addr[0]};
assign ram_di = sdram_addr[0] ? sdram_q[7:0] : sdram_q[15:8];

wire [17:0] ram_a;
wire isRam;

wire motor;

svi_mapper RamMapper
(
    .addr_i		(cpu_ram_a),
    .RegMap_i	(ay_port_b),
    .addr_o		(ram_a),
	.ram		(isRam)
);


////////////////  Console  ////////////////////////

wire [9:0] audio;
wire tape_audio_on = status[14];
wire tape_audio = (~CAS_dout) & tape_audio_on;

reg [15:0] audiomix;

wire [10:0] audiosum;
always @(posedge clk_sys) begin
	if(audiosum[10])
		audiomix <= 16'hffff;
	else
		audiomix <= {audiosum[9:0],6'b0};
	audiosum <= audio+{4'b0000,{6{tape_audio}}};
end


dac #(16) dac_l (
   .clk_i        (clk_sys),
   .res_n_i      (1      ),
   .dac_i        (audiomix),
   .dac_o        (AUDIO_L)
);

assign DAC_L={audio,6'b0};
assign DAC_R={audio,6'b0};
assign AUDIO_R=AUDIO_L;


wire CLK_VIDEO = clk_sys;

wire [7:0] R,G,B,ay_port_b;
wire hblank, vblank;
wire hsync, vsync;

wire [31:0] joya = status[3] ? joy1 : joy0;
wire [31:0] joyb = status[3] ? joy0 : joy1;


wire svi_audio_in = status[15] ? tape_in : (CAS_status != 0 ? CAS_dout : 1'b0);

cv_console console
(
	.clk_i(clk_sys),
	.clk_en_10m7_i(ce_10m7),
	.clk_en_5m3_i(ce_5m3),
	.reset_n_i(~reset),

   .svi_row_o(svi_row),
   .svi_col_i(svi_col),	
	
	.svi_tap_i(svi_audio_in),//status[15] ? tape_in : (CAS_status != 0 ? CAS_dout : 1'b0)),

   .motor_o(motor),

	.joy0_i(~{joya[4],joya[0],joya[1],joya[2],joya[3]}), //SVI {Fire,Right, Left, Down, Up} // HPS {Fire,Up, Down, Left, Right}
	.joy1_i(~{joyb[4],joyb[0],joyb[1],joyb[2],joyb[3]}),

	.cpu_ram_a_o(cpu_ram_a),
	.cpu_ram_we_n_o(ram_we_n),
	.cpu_ram_ce_n_o(ram_ce_n),
	.cpu_ram_rd_n_o(ram_rd_n),
	.cpu_ram_d_i(ram_di),
	.cpu_ram_d_o(ram_do),

	.ay_port_b(ay_port_b),
	
	.vram_a_o(vram_a),
	.vram_we_o(vram_we),
	.vram_d_o(vram_do),
	.vram_d_i(vram_di),

	.border_i(status[6]),
	.rgb_r_o(R),
	.rgb_g_o(G),
	.rgb_b_o(B),
	.hsync_n_o(hsync),
	.vsync_n_o(vsync),
	.hblank_o(hblank),
	.vblank_o(vblank),

	.audio_o(audio)
);


/////////////////  VIDEO  /////////////////////////


wire [2:0] scale = status[9:7];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

// AMR - use standard video processing chain from MiST-modules.
// (The previous video chain worked on all platforms except TC64v2,
// where it obscured the right part of the screen with a vertical stripe.)


mist_video #(.OSD_AUTO_CE(1'b1), .SD_HCNT_WIDTH(10), .VIDEO_CLEANER(1'b1)) video
 (
	// master clock
	// it should be 4x (or 2x) pixel clock for the scandoubler
	.clk_sys(CLK_VIDEO),

	// OSD SPI interface
	.SPI_SCK(SPI_SCK),
	.SPI_SS3(SPI_SS3),
	.SPI_DI(SPI_DI),

	// scanlines (00-none 01-25% 10-50% 11-75%)
	.scanlines(status[8:7]),

	// non-scandoubled pixel clock divider:
	// 0 - clk_sys/4, 1 - clk_sys/2, 2 - clk_sys/3, 3 - clk_sys/4, etc
	.ce_divider(3'd3),

	// 0 = HVSync 31KHz, 1 = CSync 15KHz
	.scandoubler_disable(forced_scandoubler),
	// YPbPr always uses composite sync
	.ypbpr(ypbpr),

	.rotate(0),

	.blend(1'b0),

	.R(R[7:2]),
	.G(G[7:2]),
	.B(B[7:2]),

	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hsync),
	.VSync(vsync),

	// MiST video output signals
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_HB(),
	.VGA_VB(),
	.VGA_DE()
);



/////////////////  Tape In   /////////////////////////

wire tape_in;
assign tape_in = UART_RX;


///////////// OSD CAS load //////////

wire CAS_dout;
wire [2:0] CAS_status;
wire play, rewind;
wire CAS_rd;
wire [25:0] CAS_addr;
wire [7:0] CAS_di;

wire [25:0] CAS_ram_addr;
reg  [17:0] CAS_end_addr;
wire CAS_ram_wren, CAS_ram_cs;
wire ioctl_isCAS = (ioctl_index[5:0] == 6'd2);


assign play = ~motor;
assign rewind = status[13] | (ioctl_download && ioctl_isCAS) | reset; //status[13];

wire CAS_ack;
wire CAS_dl;
reg CAS_wreq;
wire [1:0] CAS_ds;
wire [15:0] CAS_q;

assign CAS_dl=(ioctl_download && ioctl_isCAS);
assign CAS_ds = {~CAS_ram_addr[0],CAS_ram_addr[0]};
assign CAS_di = CAS_ram_addr[0] ? CAS_q[7:0] : CAS_q[15:8];

assign CAS_ram_cs = 1'b1;
assign CAS_ram_addr[22:0] = CAS_dl ? ioctl_addr[17:0] : CAS_addr;
assign CAS_ram_addr[24:23] = 2'b11;
assign CAS_ram_wren = ioctl_wr && ioctl_isCAS; 

always @(posedge clk_sys) begin
	if(CAS_ram_wren) begin
		CAS_wreq<=~CAS_ack;
		CAS_end_addr <= ioctl_addr;
	end
end


sdram sdram
(
	.*,
	.init_n(pll_locked),
	.clk(clk_sys),
	.clkref(1'b1),

	.port1_req(sdram_req),
	.port1_ack(sdram_ack),
	.port1_we(sdram_wren),
	.port1_a(sdram_addr),
	.port1_ds(sdram_ds),
	.port1_d({sdram_din,sdram_din}),
	.port1_q(sdram_q),
  
	.port2_req(CAS_dl ? CAS_wreq : CAS_rd),
	.port2_ack(CAS_ack),
	.port2_we(CAS_dl),
	.port2_a(CAS_ram_addr),
	.port2_ds(CAS_ds),
	.port2_d({ioctl_dout,ioctl_dout}),
	.port2_q(CAS_q)
);
assign SDRAM_CKE = 1'b1;


cassette CASReader(

  .clk(clk_sys), 
  .Q(ce_21m3), //  42.666/2
  .play(play), 
  .rewind(rewind),
  .end_addr(CAS_end_addr),
  .sdram_addr(CAS_addr),
  .sdram_data(CAS_di),
  .sdram_rd(CAS_rd),
  .sdram_ack(CAS_ack),

  .data(CAS_dout),
  .status(CAS_status)

);
endmodule

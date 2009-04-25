//
// pdp-11 in verilog - cpu
// copyright Brad Parker <brad@heeltoe.com> 2009
//
// Basic pdp-11/34ish cpu implementation
// current with no mmu or split I & D
//
// cpu expects a bus interface which contains ram and unibus
// cpu allows dma to occur when "bus_arbitrate" is asserted
// cpu acks interrupts via "interupt_ack_ipl"
//
// bus reports done via bus_ack
// bus reports errors via bus_error
// bus reports interrupts via ipl lines in bus_int_ipl
// bus assert bus_int_vector until acked
// bus can write psw by asserting psw_io_wr
//

`include "ipl_below.v"
`include "add8.v"
`include "execute.v"

module pdp11(clk, reset, initial_pc, halted, waited, trapped,
	     bus_addr, bus_data_out, bus_data_in,
	     bus_rd, bus_wr, bus_byte_op,
	     bus_arbitrate, bus_ack, bus_error,
	     bus_int, bus_int_ipl, bus_int_vector, interrupt_ack_ipl, 
	     pc, psw, psw_io_wr);

   input clk, reset;
   input [15:0] initial_pc;
   output 	halted;
   output 	waited;
   output 	trapped;
   
   output [21:0] bus_addr;
   input [15:0]  bus_data_in;
   output [15:0] bus_data_out;
   output 	 bus_rd, bus_wr, bus_byte_op;
   output 	 bus_arbitrate;
   input 	 bus_ack, bus_error;
   input 	 bus_int;
   input [7:0] 	 bus_int_ipl, bus_int_vector;
   output [7:0]  interrupt_ack_ipl;
   output [15:0] psw;
   output [15:0] pc;
   input 	 psw_io_wr;

   reg 		 interrupt;
   reg [7:0] 	 interrupt_ack_ipl;

   // state
   reg 		halted;
   reg 		waited;

   wire 	trap;
   reg 		trap_bpt;
   reg 		trap_iot;
   reg 		trap_emt;
   reg 		trap_trap;
   reg 		trap_odd;
   reg 		trap_oflo;
   reg 		trap_bus;
   reg 		trap_ill;
   reg 		trap_res;
   reg 		trap_priv;

   reg 		trace_inhibit;
   
   reg [7:0] 	vector;

   wire 	trace;
   wire 	odd_fetch;
   wire 	odd_pc;

   reg [15:0] 	psw;

   wire 	cc_n, cc_z, cc_v, cc_c;
   wire [2:0] 	ipl;

   reg [15:0] 	r0, r1, r2, r3, r4, r5;
   reg [15:0] 	r6[0:3];

   reg [15:0] 	pc;

   // wires 
   wire [15:0] 	sp;
   
   wire 	assert_wait;
   wire 	assert_halt;
   wire 	assert_reset;
   wire 	assert_bpt;
   wire 	assert_iot;
   wire 	assert_trap_odd;
   wire 	assert_trap_oflo;
   wire 	assert_trap_ill;
   wire 	assert_trap_res;
   wire 	assert_trap_priv;
   wire 	assert_trap_emt;
   wire 	assert_trap_trap;
   wire 	assert_trap_bus;

   wire 	assert_trace_inhibit;

   wire [3:0] 	isn_15_12;
   wire [6:0] 	isn_15_9;
   wire [10:0] 	isn_15_6;
   wire [5:0] 	isn_11_6;
   wire [2:0] 	isn_11_9;
   wire [5:0] 	isn_5_0;

   wire 	is_isn_rss;
   wire 	is_isn_rdd;
   wire 	is_isn_rxx;
   wire 	is_isn_r32;
   wire 	is_isn_byte;
   wire 	is_isn_mfpx;
   wire 	is_isn_mtpx;
   wire 	is_illegal;
   wire 	is_reserved;
   wire 	no_operand;
   wire 	store_result;
   wire 	store_result32;
   wire 	store_ss_reg;

   wire 	need_srcspec_dd_word,
		need_srcspec_dd_byte,
		need_srcspec_dd;

   wire 	need_destspec_dd_word,
		need_destspec_dd_byte,
		need_destspec_dd,
		need_pop_reg,
		need_pop_pc_psw,
		need_push_state,
		need_dest_data,
		need_src_data;

   wire 	need_s1,
		need_s2,
		need_s4,
		need_d1,
		need_d2,
		need_d4;

   wire [15/*21*/:0] 	dd_ea_mux;
   wire [15/*21*/:0] 	ss_ea_mux;

   wire [15/*21*/:0] 	new_pc;
   wire 	latch_pc;

   wire 	latch_sp;

   wire 	new_cc_n, new_cc_z, new_cc_v, new_cc_c;
   wire 	latch_cc;

   wire [3:0] 	new_psw_cc;
   wire [2:0] 	new_psw_prio;
   wire 	latch_psw_prio;

   // regs
   reg [15:0] 	isn;
   reg [15/*21*/:0] 	dd_ea;
   reg [15/*21*/:0] 	ss_ea;

   wire [2:0] 	dd_mode, dd_reg;

   wire 	dd_dest_mem,
		dd_dest_reg,
		dd_ea_ind,
		dd_post_incr,
		dd_pre_dec;

   wire [15:0] 	new_dd_reg_post_incr;
   wire [15:0] 	new_dd_reg_pre_decr;
   wire [15:0] 	new_dd_reg_incdec;
   
   wire [15:0] 	new_ss_reg_post_incr;
   wire [15:0] 	new_ss_reg_pre_decr;
   wire [15:0] 	new_ss_reg_incdec;
   
   wire [2:0] 	ss_mode, ss_reg;

   wire [15:0] 	ss_reg_value;	// regs[ss_reg]
   wire [15:0] 	ss_rego1_value;	// regs[ss_reg|1]
   wire [15:0] 	dd_reg_value;	// regs[dd_reg]

   // regs
   reg [15:0] 	ss_data;	// result of s states
   reg [15:0] 	dd_data;	// result of d states
   reg [15:0] 	e1_data;	// result of e states
   reg [15:0] 	e32_data;	// result of e states (high order bits)

   wire 	ss_ea_ind,
		ss_post_incr,
		ss_pre_dec;

   wire [15:0] 	pc_mux;
   wire [15:0] 	sp_mux;

   wire [15:0] 	ss_data_mux;
   wire [15:0] 	dd_data_mux;
   wire [15:0] 	e1_data_mux;

   wire [15:0] 	e1_result;
   wire [15:0] 	e32_result;
   wire 	e1_advance;
   
   // cpu modes
   parameter 	mode_kernel = 2'b00;
   parameter 	mode_super  = 2'b01;
   parameter 	mode_undef  = 2'b10;
   parameter 	mode_user   = 2'b11;

   wire [1:0] 	current_mode;
   wire [1:0] 	previous_mode;

   //
   // main cpu states
   //
   // f1 fetch;	   clock isn
   // c1 decode;
   //
   // s1 source1;	clock ss_data
   // s2 source2;	clock ss_data
   // s3 source3;	clock ss_data
   // s4 source4;	clock ss_data
   //
   // d1 dest1;	   	clock dd_data
   // d2 dest2;	   	clock dd_data
   // d3 dest3;	   	clock dd_data
   // d4 dest4;	   	clock dd_data
   //
   // e1 execute;	clock pc, sp & reg+-
   // w1 writeback;	clock e1_result
   //
   // o1 pop pc	   	mem read
   // o2 pop psw	mem read
   // o3 pop reg	mem read
   //
   // p1 push sp	mem write
   //
   // t1 push psw	mem write
   // t2 push pc	mem write
   // t3 read pc	mem read
   // t4 read psw	mem read
   //
   // i1 interrupt wait
   //
   // minimum states/instructions = 3
   // maximum states/instructions = 12
   //
   // mode,symbol,ea1	ea2		ea3		data		side-eff
   // 
   // 0	R	x	x		x		R		x
   // 1	(R)	R	x		x		M[R]		x
   // 2	(R)+	R	X		x		M[R]		R<-R+n
   // 3	@(R)+	R	M[R]		x		M[M[R]]		R<-R+2
   // 4	-(R)	R-2	x		x		M[R-2]		R<-R-n
   // 5	@-(R)	R-2	M[R-2]		x		M[M[R-2]]	R<-R-2
   // 6	X(R)	PC	M[PC]+R		x		M[M[PC]+R]	x
   // 7	@X(R)	PC	M[PC]+R		M[M[PC]+R]	M[M[M[PC]+R]]	x
   //
   // mode 0 -
   //  f1  pc++
   //  c1
   //  d1  dd_data = r
   //  e1  e1_result
   //             
   // mode 1 -
   //  f1  pc++
   //  c1
   //  d1  dd_ea = r
   //  d4  dd_data = bus_data	optional
   //  e1  e1_result
   //
   // mode 2 -
   //  f1  pc++
   //  c1
   //  d1  dd_ea = r, r++
   //  d4  dd_data = bus_data	optional
   //  e1  e1_result
   //
   // mode 3 -
   //  f1  pc++
   //  c1  dd_ea = r
   //  d1  dd_ea = bus_data, r++
   //  d4  dd_data = bus_data	optional
   //  e1  e1_result
   //
   // mode 4 -
   //  f1  pc++
   //  c1
   //  d1  dd_ea = r-x, r--
   //  d4  dd_data = bus_data	optional
   //  e1  e1_result
   //
   // mode 5 -
   //  f1  pc++
   //  c1
   //  d1  dd_ea = r-x, r--
   //  d2  dd_ea = bus_data
   //  d4  dd_data = bus_data	optional
   //  e1  e1_result
   //
   // mode 6 -
   //  f1  pc++
   //  c1
   //  d1  dd_ea = pc, pc++
   //  d2  dd_ea = bus_data + regs[dd_reg]
   //  d4  dd_data = bus_data	optional
   //  e1  e1_result
   //
   // mode 7 -
   //  f1  pc++
   //  c1
   //  d1  dd_ea = pc, pc++
   //  d2  dd_ea = bus_data + regs[dd_reg]
   //  d3  dd_ea = bus_data
   //  d4  dd_data = bus_data	optional
   //  e1  e1_result
   //

   parameter 	h1 = 5'b00000;
   parameter 	f1 = 5'b00001;
   parameter 	c1 = 5'b00010;
   parameter 	s1 = 5'b00011;
   parameter 	s2 = 5'b00100;
   parameter 	s3 = 5'b00101;
   parameter 	s4 = 5'b00110;
   parameter 	d1 = 5'b00111;
   parameter 	d2 = 5'b01000;
   parameter 	d3 = 5'b01001;
   parameter 	d4 = 5'b01010;
   parameter 	e1 = 5'b01011;
   parameter 	w1 = 5'b01100;
   parameter 	o1 = 5'b01101;
   parameter 	o2 = 5'b01110;
   parameter 	o3 = 5'b01111;
   parameter 	p1 = 5'b10001;
   parameter 	t1 = 5'b10010;
   parameter 	t2 = 5'b10011;
   parameter 	t3 = 5'b10100;
   parameter 	t4 = 5'b10101;
   parameter 	i1 = 5'b10110;

   wire [4:0] 	new_istate;
   reg [4:0] 	istate;

   //
   wire        enable_execute;
   
   assign      enable_execute = istate == e1 &&
				~is_illegal && ~is_reserved &&
				~trap_odd;
  
   //
   // execute unit
   //
   execute exec1(.clk(clk), .reset(reset),
		 .enable(enable_execute),
		 .pc(pc), .psw(psw),
		 .ss_data(ss_data), .dd_data(dd_data),
		 .cc_n(cc_n), .cc_z(cc_z), .cc_v(cc_v), .cc_c(cc_c),
		 .current_mode(current_mode),

		 .dd_ea(dd_ea),
		 .ss_reg(ss_reg),
		 
		 .ss_reg_value(ss_reg_value),
		 .ss_rego1_value(ss_rego1_value),
		 
		 .isn(isn),  .r5(r5),

		 .assert_halt(assert_halt),
		 .assert_wait(assert_wait),
		 .assert_trap_priv(assert_trap_priv),
		 .assert_trap_emt(assert_trap_emt), 
		 .assert_trap_trap(assert_trap_trap),
		 .assert_bpt(assert_bpt),
		 .assert_iot(assert_iot),
		 .assert_reset(assert_reset),
		 .assert_trace_inhibit(assert_trace_inhibit),
		 
		 .e1_result(e1_result), .e32_result(e32_result),
		 .e1_advance(e1_advance),

		 .new_pc(new_pc), .latch_pc(latch_pc), .latch_sp(latch_sp),
		 
		 .new_cc_n(new_cc_n), .new_cc_z(new_cc_z), 
		 .new_cc_v(new_cc_v), .new_cc_c(new_cc_c),

		 .latch_cc(latch_cc),
		 .latch_psw_prio(latch_psw_prio),
		 .new_psw_prio(new_psw_prio));
   
   //
   // effective address mux;
   // set address of next memory operation in various states
   //

   //
   // source ea calculation:
   // decode - load from register or pc
   // s1 - if mode 6,7 add result of pc+2 fetch to reg
   // s2 - result of fetch
   // t1 - trap vector
   // t4 - incr ea
   //
   
   assign ss_ea_mux =
     (istate == c1 || istate == s1) ?
		     (ss_mode == 0 ? ss_reg_value :
		      ss_mode == 1 ? ss_reg_value :
		      ss_mode == 2 ? ss_reg_value :
		      ss_mode == 3 ? ss_reg_value :
		      ss_mode == 4 ? (ss_reg_value -
      		       		((is_isn_byte && ss_reg < 6) ? 16'd1 : 16'd2)) :
		      ss_mode == 5 ? (ss_reg_value -
      		       		((is_isn_byte && ss_reg < 6) ? 16'd1 : 16'd2)) :
		      ss_mode == 6 ? pc :
		      ss_mode == 7 ? pc :
		      16'b0) :

     istate == s2 ?
		     (ss_mode == 3 ? bus_data_in :
		      ss_mode == 5 ? bus_data_in :
		      ss_mode == 6 ? (bus_data_in + ss_reg_value) :
		      ss_mode == 7 ? (bus_data_in + ss_reg_value) :
		      ss_ea) :
		     
     istate == s3 ? bus_data_in :

     istate == t1 ? ((odd_pc |
		      trap_odd | trap_oflo | trap_bus | trap_res) ? 16'o4 :
		     trap_ill ? 16'o10 :
		     trap_priv ? 16'o10 :
		     (trap_bpt | (trace && ~trap_iot)) ? 16'o14 :
		     trap_iot ? 16'o20 :
		     trap_emt ? 16'o30 :
		     trap_trap ? 16'o34 :
		     interrupt ? { 8'b0, vector } :
		     16'd0) :

     istate == t2 ? ss_ea :
     istate == t3 ? ss_ea + 16'd2 :
     istate == t4 ? ss_ea + 16'd2 :
		     16'd0;

   //
   // dest ea calculation:
   // decode - load from register or pc
   // d1 - if mode 6,7 add result of pc+2 fetch to reg
   // d2 - result of fetch
   //
   assign dd_ea_mux = (istate == c1 || istate == d1) ?
		      (dd_mode == 0 ? dd_reg_value :
		       dd_mode == 1 ? dd_reg_value :
		       dd_mode == 2 ? dd_reg_value :
		       dd_mode == 3 ? dd_reg_value :
		       dd_mode == 4 ? (dd_reg_value -
		       		((is_isn_byte && dd_reg < 6) ? 16'd1 : 16'd2)) :
		       dd_mode == 5 ? (dd_reg_value -
				((is_isn_byte && dd_reg < 6) ? 16'd1 : 16'd2)) :
		       dd_mode == 6 ? pc :
		       dd_mode == 7 ? pc :
		       16'b0) :

		      istate == d2 ?
		      (dd_mode == 3 ? bus_data_in :
		       dd_mode == 5 ? bus_data_in :
		       dd_mode == 6 ? (bus_data_in + dd_reg_value) :
		       dd_mode == 7 ? (bus_data_in + dd_reg_value) :
		       dd_ea) :

		      istate == d3 ? bus_data_in :
		      dd_ea;


   //
   // mux various data sources into ss, dd & e1 data registers
   //
   assign ss_data_mux =
	       (istate == c1 && (ss_mode == 0 || is_isn_rxx)) ? ss_reg_value :
	       (istate == s4) ? bus_data_in :
	       16'b0;

   assign dd_data_mux =
	       (istate == c1 && (isn_15_6 == 10'o1067)) ? psw[7:0] : // mfps 
	       (istate == c1 && dd_mode == 0) ? dd_reg_value :
	       (istate == d4) ? bus_data_in :
	       16'b0;

   assign e1_data_mux =
	       (istate == e1) ? e1_result :
	       16'b0;


   //
   // mux sources of pc changes into new pc
   //
   wire trap_or_int = trap || interrupt || trace || odd_pc;

   assign pc_mux =
	  (istate == f1 && !trap_or_int                  ) ? pc + 16'd2 :
	  (istate == s1 && (ss_mode == 6 || ss_mode == 7)) ? pc + 16'd2 :
	  (istate == d1 && (dd_mode == 6 || dd_mode == 7)) ? pc + 16'd2 :
	  (istate == e1 && latch_pc                      ) ? new_pc :
	  (istate == o1 || istate == t3                  ) ? bus_data_in :
	  pc;

   //
   // mux source of sp changes
   //
   assign sp_mux =
		  (istate == o1 || istate == o2 || istate == o3) ? sp + 16'd2 :
		  (istate == e1 && latch_sp) ? e1_result :
		  (istate == p1 ) ? sp - 16'd2 :
		  (istate == t1 ) ? sp - 16'd2 :
		  (istate == t2 ) ? sp - 16'd2 :
		  r6[current_mode];


   // shorthand
   assign cc_n = psw[3];
   assign cc_z = psw[2];
   assign cc_v = psw[1];
   assign cc_c = psw[0];
   assign ipl  = psw[7:5];
   
   assign sp = r6[current_mode];
   
   assign current_mode = psw[15:14];
   assign previous_mode = psw[13:12];

   //
   // psw_mux
   //
   // after e1, latch new psw cc bits or latch new prio
   // after o2|t4, latch new psw from memory read
   //
   assign new_psw_cc = {new_cc_n, new_cc_z, new_cc_v, new_cc_c};

   always @(posedge clk)
     if (reset)
	  psw <= 16'o0340;
     else
       begin
	  if (istate == e1)
	    psw <= { psw[15:8], 
		     latch_psw_prio ? new_psw_prio : psw[7:5],
		     psw[4],
		     latch_cc ? new_psw_cc : psw[3:0]};
	  else
            if (istate == o2 || istate == t4)
	      psw <= bus_data_in;
	    else
	      if (istate == w1 && psw_io_wr)
		begin
		   if (~bus_byte_op)
		     psw <= {bus_data_out[15:5], psw[4], bus_data_out[3:0]};
		   else
		     if (bus_addr[0])
		       psw <= {bus_data_out[15:8], psw[7:0]};
		     else
		       psw <= {psw[15:8], bus_data_out[7:5],
			       psw[4], bus_data_out[3:0]};
		end
       end

   //
   // instruction decode
   //
   assign isn_15_12 = isn[15:12];
   assign isn_15_9  = isn[15:9];
   assign isn_15_6  = isn[15:6];
   assign isn_11_6  = isn[11:6];
   assign isn_11_9  = isn[11:9];
   assign isn_5_0   = isn[5:0];

   assign need_destspec_dd_word =
	(isn_15_6 == 10'o0001) ||				// jmp
	(isn_15_6 == 10'o0003) ||				// swab
	(isn_15_12 == 0 && (isn_11_6 >= 6'o40 && isn_11_6 <= 6'o63))||// jsr-asl
	(isn_15_12 == 0 && (isn_11_6 >= 6'o65 && isn_11_6 <= 6'o67))||// m*,sxt
	(isn_15_12 >= 4'o01 && isn_15_12 <= 4'o06) ||		// mov-add
	(isn_15_9 >= 7'o070 && isn_15_9 <= 7'o074) || 		// mul-xor
	(isn_15_12 == 4'o10 &&
	 (isn_11_6 >= 6'o65 && isn_11_6 <= 6'o66))||		// mtpx
	(isn_15_12 == 4'o16);					// sub

   assign need_destspec_dd_byte =				// xxxb
	(isn_15_12 == 4'o10 && (isn_11_6 >= 6'o50 && isn_11_6 <= 6'o64))||
	(isn_15_12 == 4'o10 && (isn_11_6 == 6'o67)) ||		// mfps
	(isn_15_12 >= 4'o11 && isn_15_12 < 10'o0016);		// xxxb

   assign need_destspec_dd = need_destspec_dd_word | need_destspec_dd_byte;

   assign need_srcspec_dd_word = 
	 (isn_15_12 >= 4'o01 && isn_15_12 <= 4'o06) ||		// mov-add
	 (isn_15_12 == 4'o16);					// sub

   assign need_srcspec_dd_byte = 
	 (isn_15_12 >= 4'o11 && isn_15_12 <= 4'o15);		// movb-sub

   assign need_srcspec_dd = need_srcspec_dd_word | need_srcspec_dd_byte;

   assign no_operand =
	(isn_15_6 == 10'o0000 && isn_5_0 < 6'o10) ||
	(isn_15_6 == 10'o0002 && (isn_5_0 >= 6'o30 && isn_5_0 <= 6'o77)) ||
	(isn_15_12 == 0 && (isn_11_6 >= 6'o04 && isn_11_6 <= 6'o37)) ||
	(isn_15_9 == 7'o104) ||					// trap/emt
	0;

   assign is_illegal =
	(isn_15_6 == 10'o0000 && isn_5_0 > 6'o07) ||
	(isn_15_6 == 10'o0000 && isn_5_0 == 6'o07) ||		// trapa/mfpt
	(isn_15_6 == 10'o0002 && (isn_5_0 >= 6'o10 && isn_5_0 <= 6'o27)) ||
	(isn_15_12 == 4'o07 && (isn_11_9 == 5 || isn_11_9 == 6)) ||
	(isn_15_12 == 4'o17);

   assign is_reserved =
	(isn_15_6 == 10'o0001 && isn[5:3] == 3'b000) ||		// jmp rx
   	(isn_15_9 == 7'o004 && isn[5:3] == 3'b000);		// jsp rx

   assign need_pop_reg =					// rts
			(isn_15_6 == 10'o0002 && (isn_5_0 < 6'o10)) ||
			(isn_15_6 == 10'o0064) ||		// mark
			(isn_15_6 == 10'o0070) ||		// csm
			(isn[14:6] == 9'o066);			// mtpi/mtpd
   
   assign need_pop_pc_psw =					// rti, rtt
	(isn_15_6 == 0 && (isn_5_0 == 6'o02 || isn_5_0 == 6'o06));
   
   assign need_push_state =
			   (isn_15_9 == 7'o004) ||		// jsr
			   (isn[14:6] == 9'o065);		// mfpi/mfpd

   assign assert_trap_ill = is_illegal;

   assign assert_trap_res = is_reserved;

   assign odd_pc = pc[0];
   
   assign odd_fetch = (bus_rd || bus_wr) && bus_addr[0] && ~bus_byte_op;

   assign assert_trap_odd = odd_fetch;			// fetch from odd

   assign assert_trap_oflo = 				// stack overflow
		(ss_pre_dec && ss_reg == 6 && new_ss_reg_pre_decr < 16'o0400) ||
		(dd_pre_dec && dd_reg == 6 && new_dd_reg_pre_decr < 16'o0400) ||
		(trap && (sp - 16'd2) < 16'o0400);

   assign assert_trap_bus = bus_error;

   assign trace = psw[4] && !trace_inhibit;			// trace bit
   
   assign store_result32 =
			  (isn_15_9 == 7'o070) ||		// mul
			  (isn_15_9 == 7'o071) ||		// div
			  (isn_15_9 == 7'o073);			// ashc
   
   assign store_result =
		!no_operand &&
		!store_result32 &&
		!(isn_15_9 == 7'o004) &&			// jsr
		!(isn_15_9 == 7'o072) &&			// ash
		!(isn_15_9 == 7'o077) &&			// sob
		!(isn_15_6 == 10'o0001) &&			// jmp
		!(isn_15_6 == 10'o0057) &&
		!(isn_15_6 == 10'o1057) &&			// tst/tstb
		!(isn_15_6 == 10'o0064) &&			// mark
		!(isn[14:6] == 9'o065) &&			// mfpi/mfpd
		!(isn_15_12 == 4'o02) &&
		!(isn_15_12 == 4'o12) &&			// cmp/cmpb
		!(isn_15_12 == 4'o03) &&
		!(isn_15_12 == 4'o13) &&			// bit/bitb
		!((isn_15_6 >= 10'o1000) && (isn_15_6 <= 10'o1037)) &&// bcs-blo
		!((isn_15_6 >= 10'o0004) && (isn_15_6 <= 10'o0034));  // br-ble

   assign need_dest_data = 
		   !(isn_15_12 == 4'o01) &&			// mov
		   !(isn_15_12 == 4'o11) &&			// movb
		   !(isn_15_9 == 7'o04) &&			// jsr
		   !((isn_15_6 == 10'o0050) ||
		     (isn_15_6 == 10'o1050)) && 		// clr/clrb
		   !(isn_15_6 == 10'o0001);			// jmp

   assign is_isn_byte = isn[15] && !(isn_15_12 == 4'o16); 	// sub

   assign is_isn_rdd = 
		       (isn_15_9 == 7'o004) ||			// jsr
		       (isn_15_9 == 7'o074) ||			// xor
		       (isn_15_9 == 7'o077);			// sob

   assign is_isn_rss = 
		       (isn_15_9 == 7'o070) ||			// mul
		       (isn_15_9 == 7'o071) ||			// div
		       (isn_15_9 == 7'o072) ||			// ash
		       (isn_15_9 == 7'o073);			// ashc

   assign is_isn_rxx = is_isn_rdd || is_isn_rss;

   assign is_isn_r32 = (isn_15_9 == 7'o071);			// div

   assign is_isn_mfpx = (isn[14:6] == 9'o065);			// mfpi/mfpd
   assign is_isn_mtpx = (isn[14:6] == 9'o066);			// mtpi/mtpd
   
   assign need_src_data =
			 !((isn_15_6 == 10'o0050) ||
			   (isn_15_6 == 10'o1050));		// clr/clrb

			   
   // ea setup - ss
   assign ss_mode = isn[11:9];
   assign ss_reg = (isn_15_6 == 10'o0064) ? 3'd5 : isn[8:6];

   assign ss_ea_ind = ss_mode == 7;

   assign store_ss_reg = (isn_15_9 == 004 && ss_reg != 7) ||	// jsr
			 (isn_15_9 == 7'o072) ||		// ash
			 (isn_15_9 == 7'o077) ||		// sob
			 (isn_15_6 == 10'o0064);		// mark

   assign ss_post_incr = need_srcspec_dd &&
			 (ss_mode == 2 || ss_mode == 3);

   assign ss_pre_dec = need_srcspec_dd &&
		       (ss_mode == 4 || ss_mode == 5);

   // ea setup - dd
   assign dd_mode = isn[5:3];
   assign dd_reg = isn[2:0];

   assign dd_dest_mem = dd_mode != 0;
   assign dd_dest_reg = dd_mode == 0;
   assign dd_ea_ind = dd_mode == 7;

   assign dd_post_incr = need_destspec_dd &&
			 (dd_mode == 2 || dd_mode == 3);

   assign dd_pre_dec = need_destspec_dd &&
		       (dd_mode == 4 || dd_mode == 5);

   // post-incr/pre-decr values
   assign new_dd_reg_post_incr = dd_reg_value +
				 ((need_destspec_dd_byte &&
				   dd_reg < 6 && dd_mode == 2) ?
				  16'd1 : 16'd2);

   assign new_dd_reg_pre_decr = dd_reg_value - 
				((need_destspec_dd_byte &&
				  dd_reg < 6 && dd_mode == 4) ?
				 16'd1 : 16'd2);

   assign new_dd_reg_incdec = dd_post_incr ? new_dd_reg_post_incr :
			      new_dd_reg_pre_decr;
   
   assign new_ss_reg_post_incr = ss_reg_value +
				 ((need_destspec_dd_byte &&
				   ss_reg < 6 && ss_mode == 2) ?
				  16'd1 : 16'd2);

   assign new_ss_reg_pre_decr = ss_reg_value - 
				((need_destspec_dd_byte &&
				  ss_reg < 6 && ss_mode == 4) ?
				 16'd1 : 16'd2);

   assign new_ss_reg_incdec = ss_post_incr ? new_ss_reg_post_incr :
			      new_ss_reg_pre_decr;
   

   // reg values
   assign ss_reg_value = ss_reg == 0 ? r0 :
			 ss_reg == 1 ? r1 :
			 ss_reg == 2 ? r2 :
			 ss_reg == 3 ? r3 :
			 ss_reg == 4 ? r4 :
			 ss_reg == 5 ? r5 :
			 ss_reg == 6 ? r6[current_mode] :
			 pc;

   assign ss_rego1_value = (ss_reg == 3'd0 || ss_reg == 3'd1) ? r1 :
			   (ss_reg == 3'd2 || ss_reg == 3'd3) ? r3 :
			   (ss_reg == 3'd4 || ss_reg == 3'd5) ? r5 :
			   pc;

   assign dd_reg_value = dd_reg == 0 ? r0 :
			 dd_reg == 1 ? r1 :
			 dd_reg == 2 ? r2 :
			 dd_reg == 3 ? r3 :
			 dd_reg == 4 ? r4 :
			 dd_reg == 5 ? r5 :
			 dd_reg == 6 ? (is_isn_mfpx ?		// mfpi/mfpd
					r6[previous_mode] : r6[current_mode]) :
			 pc;

   // decide on next state
   assign need_s1 = need_srcspec_dd;
   assign need_d1 = need_destspec_dd;

   assign need_s2 = need_srcspec_dd && (ss_mode == 3 || ss_mode >= 5);
   assign need_d2 = need_destspec_dd && (dd_mode == 3 || dd_mode >= 5);

   assign need_s4 = need_srcspec_dd && ss_mode != 0 && need_src_data;
   assign need_d4 = need_destspec_dd && dd_mode != 0 && need_dest_data;


   // memory i/o
   assign bus_rd =
		  istate == f1 ||
		  (istate == s2 || istate == s3 || istate == s4) ||
		  (istate == d2 || istate == d3 || istate == d4) ||
		  (istate == o1 || istate == o2 || istate == o3) ||
		  (istate == t3 || istate == t4);
	   
   assign bus_wr =
	   (istate == w1 && store_result && dd_dest_mem) ||
	   istate == p1 ||
	   istate == t1 ||
	   istate == t2;

   assign bus_data_out =
		  istate == w1 ? e1_data :
		  istate == p1 ? (is_isn_mfpx ?			// mfpi/mfpd
				  dd_data : ss_reg_value) :
		  istate == t1 ? psw :
   		  istate == t2 ? pc :
		  16'b0;
   
   assign bus_addr =
		    istate == f1 ? pc :
		    istate == s2 ? ss_ea :
		    istate == s3 ? ss_ea :
		    istate == s4 ? ss_ea :
		    istate == d2 ? dd_ea :
    		    istate == d3 ? dd_ea :
    		    istate == d4 ? dd_ea :
		    istate == w1 ? dd_ea :
		    istate == o1 ? sp :
		    istate == o2 ? sp :
		    istate == o3 ? sp :
		    istate == p1 ? sp - 16'd2 :
		    istate == t1 ? sp - 16'd2 :
		    istate == t2 ? sp - 16'd2 :
		    istate == t3 ? ss_ea :
		    istate == t4 ? ss_ea :
		    16'b0;
   

   assign bus_byte_op = (istate == w1 || istate == s4 || istate == d4) ?
			is_isn_byte: 1'b0;

   //
   // clock data
   //
   always @(posedge clk)
     if (reset)
       begin
	  r0 <= 0;
	  r1 <= 0;
	  r2 <= 0;
	  r3 <= 0;
	  r4 <= 0;
	  r5 <= 0;
	  r6[0] <= 0;
	  r6[1] <= 0;
	  r6[2] <= 0;
	  r6[3] <= 0;
	  pc <= initial_pc;

	  isn <= 0;
       end
     else
       if (bus_ack)
       begin

	  if (istate != w1)
	    pc <= pc_mux; 			// pc

	  if (istate != w1 && istate != s1 && istate != d1)
	    begin
	       r6[current_mode] <= sp_mux;	// sp
`ifdef debug
	       if (r6[current_mode] != sp_mux)
		 $display("sp <- %o", sp_mux);
`endif
	    end

	  case (istate)
	    f1:
	    begin
	       // bus_rd asserted
	       isn <= bus_data_in;
`ifdef debug
	       $display(" fetch pc %o, isn %o", pc, bus_data_in);
`endif
	    end

	  c1:
	    begin
	    end

	  s1:
	    begin
`ifdef debug
               if (ss_post_incr)
		 $display(" R%d <- %o (ss r++)", ss_reg, new_ss_reg_incdec);

	       if (ss_pre_dec)
		 $display(" R%d <- %o (ss r--)", ss_reg, new_ss_reg_incdec);
`endif

	       if (ss_post_incr || ss_pre_dec)
		 case (ss_reg)
		   0: r0 <= new_ss_reg_incdec;
		   1: r1 <= new_ss_reg_incdec;
		   2: r2 <= new_ss_reg_incdec;
		   3: r3 <= new_ss_reg_incdec;
		   4: r4 <= new_ss_reg_incdec;
		   5: r5 <= new_ss_reg_incdec;
		   6: r6[current_mode] <= new_ss_reg_incdec;
		   7: pc <= new_ss_reg_incdec;
		 endcase
	    end // case: s1
	  
	  s2:
	    begin
	       // bus_rd asserted
	    end

	  s3:
	    begin
	       // bus_rd asserted
	    end

	  s4:
	    begin
	       // bus_rd asserted
	    end

	  d1:
	    begin
`ifdef debug
               if (dd_post_incr)
		 $display(" R%d <- %o (dd r++)", dd_reg, new_dd_reg_incdec);

	       if (dd_pre_dec)
		 $display(" R%d <- %o (dd r--)", dd_reg, new_dd_reg_incdec);
`endif

	       if (dd_post_incr || dd_pre_dec)
		 case (dd_reg)
		   0: r0 <= new_dd_reg_incdec;
		   1: r1 <= new_dd_reg_incdec;
		   2: r2 <= new_dd_reg_incdec;
		   3: r3 <= new_dd_reg_incdec;
		   4: r4 <= new_dd_reg_incdec;
		   5: r5 <= new_dd_reg_incdec;
		   6: r6[current_mode] <= new_dd_reg_incdec;
		   7: pc <= new_dd_reg_incdec;
		 endcase
	    end

	  d2:
	    begin
	       // note: cycle needs to be long enough for memory read
	       // bus_rd asserted
	    end

	  d3:
	    begin
	       // bus_rd asserted
	    end

	  d4:
	    begin
	       // bus_rd asserted
	       // bus_addr <= dd_ea
	    end

	  e1:
	    begin
	    end
	  
	  w1:
	    begin
	       // bus_wr asserted if (store_result && dd_dest_mem)
	       if (store_result && dd_dest_mem)
		 begin
		 end
	       else
		 if (store_result && dd_dest_reg)
		   begin
		      $display(" r%d <- %0o (dd)", dd_reg, e1_data);
		      case (dd_reg)
			0: r0 <= e1_data;
			1: r1 <= e1_data;
			2: r2 <= e1_data;
			3: r3 <= e1_data;
			4: r4 <= e1_data;
			5: r5 <= e1_data;
			6:
			  begin
			     if (is_isn_mtpx)			// mtpi/mtpd
			       r6[previous_mode] <= e1_data;
			     else
			       r6[current_mode] <= e1_data;
			  end
			7: pc <= e1_data;
		      endcase
		   end
		 else
		   if (store_ss_reg)
		     begin
			$display(" r%d <- %0o (ss)", ss_reg, e1_data);
			case (ss_reg)
			  0: r0 <= e1_data;
			  1: r1 <= e1_data;
			  2: r2 <= e1_data;
			  3: r3 <= e1_data;
			  4: r4 <= e1_data;
			  5: r5 <= e1_data;
			  6: r6[current_mode] <= e1_data;
			  7: pc <= e1_data;
			endcase
		     end
		   else
		     if (store_result32)
		       begin
			  $display(" r%0d <- %0o (e32)",
				   ss_reg, e32_data);
			  $display(" r%0d <- %0o (e32)",
				   ss_reg|1, e1_data);

			  //regs[ss_reg    ] <= e32_data;
			  //regs[ss_reg | 1] <= e1_data;

			  case (ss_reg)
			    0: begin r0 <= e32_data; r1 <= e1_data; end
			    1: r1 <= e1_data;
			    2: begin r2 <= e32_data; r3 <= e1_data; end
			    3: r3 <= e1_data;
			    4: begin r4 <= e32_data; r5 <= e1_data; end
			    5: r5 <= e1_data;
			    6: begin
			       r6[current_mode] <= e32_data;
			       pc <= e1_data;
			    end
			    7: pc <= e1_data;
			  endcase
		       end
	    end // case: w1
	  

	  o1:
	    begin
	       // pop: sp_mux <= sp + 2
	       // bus_rd asserted
	    end

	  o2:
	    begin
	       // pop: sp_mux <= sp + 2
	       // bus_rd asserted
	    end

	  o3:
	    begin
	       // pop: sp_mux <= sp + 2
	       // bus_rd asserted
	       // bus_addr <= sp
	    end


	  p1:
	    begin
	       // push: sp_mux <= sp - 2
	       // bus_wr asserted
	       // bus_data_out <= regs[ss_reg]
	       // bus_addr <= sp - 2
	    end

	  t1:
	    begin
	       // push: sp_mux <= sp - 2
	       // bus_wr asserted
	       // bus_data_out <= psw
	    end

	  t2:
	    begin
	       // push: sp_mux <= sp - 2
	       // bus_wr asserted
	       // bus_data_out <= pc
	    end

	  t3:
	    begin
	       // push: sp_mux <= sp - 2
	       // bus_rd asserted
	    end

	  t4:
	    begin
	       // bus_rd asserted
	    end

	  i1:
	    begin
	    end
	endcase // case(istate)
       end
   
   
   //
   // check_for_traps
   //
   wire ok_to_assert_trap;
   wire ok_to_reset_trap;
   wire ok_to_reset_trace_inhibit;
   
   assign ok_to_assert_trap =
			     istate == f1 || istate == c1 || istate == e1 ||
			     istate == s4 || istate == d4 || istate == w1;

   assign ok_to_reset_trap = istate == t1;

   assign ok_to_reset_trace_inhibit = istate == f1;

   assign trapped = trap;
   
   assign trap =
            trap_bpt || trap_iot || trap_emt || trap_trap ||
	    trap_res || trap_ill || trap_odd || trap_oflo ||
	    trap_priv || trap_bus;

   always @(posedge clk)
     if (reset)
       begin
	     trap_odd <= 0;
	     trap_oflo <= 0;
	     trap_ill <= 0;
	     trap_res <= 0;
	     trap_priv <= 0;
	     trap_bpt <= 0;
	     trap_iot <= 0;
	     trap_emt <= 0;
	     trap_trap <= 0;
	     trap_bus <= 0;
	     trace_inhibit <= 0;
       end
   else
     begin
	if (ok_to_reset_trap)
	  begin
	     trap_odd <= 0;
	     // allow double trap if trap causes oflo
	     if (~trap_odd && ~trap_ill && ~trap_res &&
		 ~trap_priv && ~trap_bpt && ~trap_iot &&
		 ~trap_emt && ~trap_trap && ~trap_bus)
	       trap_oflo <= 0;
	     trap_ill <= 0;
	     trap_res <= 0;
	     trap_priv <= 0;
	     trap_bpt <= 0;
	     trap_iot <= 0;
	     trap_emt <= 0;
	     trap_trap <= 0;
	     trap_bus <= 0;
	  end
	else
	  if (ok_to_assert_trap)
	    begin
	       if (assert_trap_odd)
		    trap_odd <= 1;
	
	       if (assert_trap_oflo)
		    trap_oflo <= 1;
	
	       if (assert_trap_bus)
		    trap_bus <= 1;

`ifdef debug
	       if (trace)
		 $display("trace pc %o, addr %o", pc, bus_addr);
	       if (assert_trap_bus)
		 $display("buserr pc %o, addr %o", pc, bus_addr);
`endif
	       
	       if (istate == c1)
		 begin
		    if (assert_trap_ill)
		      trap_ill <= 1;

		    if (assert_trap_res)
		      trap_res <= 1;

`ifdef debug
		    if (assert_trap_ill)
		      begin
	       		 $display("trap_ill pc %o", pc);
			 $display("trap_ill is_illegal %b, isn %o",
				  is_illegal, isn);
		      end
		    if (assert_trap_res)
		      $display("trap_res pc %o", pc);
`endif
		 end

               if (istate == e1)
		 begin
		    if (assert_trap_priv)
                      trap_priv <= 1;

		    if (assert_bpt)
                      trap_bpt <= 1;

		    if (assert_iot)
                      trap_iot <= 1;

		    if (assert_trap_emt)
                      trap_emt <= 1;

		    if (assert_trap_trap)
                      trap_trap <= 1;

		    if (assert_trace_inhibit)
		      trace_inhibit <= 1;

`ifdef debug
		    if (assert_trap_emt)
		      $display("trap_emt pc %o", pc);
`endif
		 end
	    end // if (ok_to_assert_trap)

	if (ok_to_reset_trace_inhibit)
	  trace_inhibit <= 0;

        if (trap)
	  begin
             $display("trap: asserts ");
	     $display(" %o %o %o %o %o %o %o %o %o %o",
		      trap_bpt, trap_iot, trap_emt, trap_trap,
		      trap_res, trap_ill, trap_odd, trap_oflo,
		      trap_priv, trap_bus);

             if (assert_trap_priv) $display("PRIV ");
             if (assert_trap_odd) $display("ODD ");
             if (assert_trap_oflo) $display("OFLO");
             if (assert_trap_ill) $display("ILL ");
             if (assert_trap_res) $display("RES ");
             if (assert_bpt) $display("BPT ");
             if (assert_iot) $display("IOT ");
             if (assert_trap_emt) $display("EMT ");
             if (assert_trap_trap) $display("TRAP ");
             if (assert_trap_bus) $display("BUS ");
             $display("");

             $display("trap: %d", trap);
	  end // if (trap)
     end // always @ (posedge clk)

   //
   // halt & wait entry
   //
   always @(posedge clk)
     if (reset)
       begin
	  halted <= 0;
	  waited <= 0;
       end
     else
       if (istate == e1)
	 begin
	    if (assert_halt)
	      begin
`ifdef debug
		 $display("assert_halt");
`endif
		 halted <= 1;
	      end

	    if (assert_wait)
	      begin
`ifdef debug
		 $display("assert_wait");
`endif
		 waited <= 1;
	      end
	 end

   //
   // check_for_interrupts
   //
   wire ok_to_assert_int;

   assign ok_to_assert_int = istate == f1 || istate == i1 ||
			     istate == s4 || istate == d4 || istate == w1;

   wire ipl_below;

   ipl_below_func ibf(ipl, bus_int_ipl, ipl_below);
   
   always @(posedge clk)
     if (reset)
       begin
	  interrupt <= 0;
	  interrupt_ack_ipl <= 0;
       end
     else
       if (ok_to_assert_int)
	 begin
          if (bus_int & ipl_below)
	    begin
               interrupt <= 1;
	       interrupt_ack_ipl <= bus_int_ipl;
               vector <= bus_int_vector;
//`ifdef debug
               $display("cpu: XXX interrupt asserts; vector %o",
			bus_int_vector);
//`endif
            end
	  else
	    begin
	       interrupt_ack_ipl <= 0;
	    end
       end
     else
       if (istate == t4)
	 begin
	    interrupt <= 0;
	    interrupt_ack_ipl <= 0;
	    vector <= 0;
	 end
   
`ifdef debug_cpu_int
   always @(posedge clk)
     if (ok_to_assert_int && bus_int)
       $display("cpu: XXX cpu int; ipl %o, int_ipl %b, vector %o, ack_ipl %b below %b",
		ipl, bus_int_ipl, bus_int_vector,
		interrupt_ack_ipl, ipl_below);
`endif

   
//`ifdef debug_cpu_int
   always @(posedge clk)
     if (interrupt)
       $display("cpu: XXX cpu int; vector %o, istate %o, interrupt_ack_ipl %o",
		vector, istate, interrupt_ack_ipl);
   
   always @(posedge clk)
     if (interrupt_ack_ipl)
       $display("cpu: XXX cpu int_ack; interrupt_ack_ipl %b, istate %o",
		interrupt_ack_ipl, istate);
//`endif   

   //
   // calculate next state
   //
   assign new_istate = istate == f1 ? ((trap||interrupt||trace||odd_pc) ? t1 :
        			       c1) :

		       istate == c1 ? ((is_illegal || is_reserved) ? f1 :
        			       no_operand ? e1 :
        			       need_s1 ? s1 :
        			       need_d1 ? d1 :
				       e1):

		       istate == s1 ? (need_s2 ? s2 :
				       need_s4 ? s4 :
				       d1) :
		       istate == s2 ? (ss_ea_ind ? s3 :
        			       need_s4 ? s4 :
				       d1) :
		       istate == s3 ? s4 :
		       istate == s4 ? d1 :

		       istate == d1 ? (need_d2 ? d2 : 
        			       need_d4 ? d4 :
        			       need_push_state ? p1 :
        			       e1) :
		       istate == d2 ? (dd_ea_ind ? d3 :
        			       need_d4 ? d4 :
        			       need_push_state ? p1 :
        			       e1) :
		       istate == d3 ? (need_d4 ? d4 :
        			       need_push_state ? p1 :
        			       e1) :
		       istate == d4 ? (need_push_state ? p1 :
        			       e1) :

		       istate == e1 ? (~e1_advance ? e1 :
				       need_pop_reg ? o3 :
				       need_pop_pc_psw ? o1 :
        			       w1) :

		       istate == w1 ? (halted ? h1 :
				       waited ? i1 :
				       f1) :

		       istate == o1 ? o2 :
		       istate == o2 ? f1 :
		       istate == o3 ? w1 :

		       istate == p1 ? e1 :

		       istate == t1 ? t2 :
		       istate == t2 ? t3 :
		       istate == t3 ? t4 :
		       istate == t4 ? f1 :

		       istate == i1 ? (interrupt ? f1 : i1) :

		       istate == h1 ? h1 :
		       istate;

  always @(posedge clk)
    if (reset)
      istate <= f1;
    else
      istate <= bus_ack ? new_istate : istate;

   assign bus_arbitrate = istate == f1;

   //
   // clock internal registes
   //
   always @(posedge clk)
     if (reset)
       begin
	  ss_data <= 0;
	  dd_data <= 0;
	  ss_ea <= 0;
	  dd_ea <= 0;
	  e1_data <= 0;
	  e32_data <= 0;
       end
     else
       if (bus_ack)
       begin
	  ss_ea <= (istate == c1 ||
		    istate == s1 ||
		    istate == s2 ||
		    istate == s3 ||
		    istate == d1 ||
		    istate == d2 ||
		    istate == d3 ||
		    istate == t1 ||
		    istate == t3) ?
		   ss_ea_mux : ss_ea;

	  dd_ea <= (istate == c1 ||
		    istate == s1 ||
		    istate == s2 ||
		    istate == s3 ||
		    istate == d1 ||
		    istate == d2 ||
		    istate == d3) ?
		   dd_ea_mux : dd_ea;

	  // clock data at c1 for register and s4 for M[] 
	  if (istate == c1 || istate == s4)
	       ss_data <= ss_data_mux;

	  // clock data at c1 for register and d4 for M[] 
	  if (istate == c1 || istate == d4)
	       dd_data <= dd_data_mux;

	  e1_data <= (istate == e1/* || istate == w1*/) ? e1_data_mux :
		     (istate == o3) ? bus_data_in :
		     e1_data;

	  e32_data <= istate == e1  ? e32_result : e32_data;
       end

   //
   //debug
   //

`ifdef minimal_debug
   always @(posedge clk)
     #2 begin
   	case (istate)
	  f1:
	    begin
	       $display("f1: pc=%0o, sp=%0o, psw=%0o ipl%d n%d z%d v%d c%d (%0o %0o %0o %0o %0o %0o %0o %0o)",
			pc, sp, psw, ipl, cc_n, cc_z, cc_v, cc_c,
			r0, r1, r2, r3, r4, r5, sp, pc);
	       $display("    trap=%d, interrupt=%d, trace_inhibit=%d",
			trap, interrupt, trace_inhibit);
	    end // case: f1
	endcase
     end
`endif

`ifdef debug
   always @(posedge clk)
     #2 begin
   	case (istate)
	  f1:
	    begin
	       $display("f1: pc=%0o, sp=%0o, psw=%0o ipl%d n%d z%d v%d c%d (%0o %0o %0o %0o %0o %0o %0o %0o)",
			pc, sp, psw, ipl, cc_n, cc_z, cc_v, cc_c,
			r0, r1, r2, r3, r4, r5, sp, pc);
	       $display("    trap=%d, interrupt=%d, trace_inhibit=%d",
			trap, interrupt, trace_inhibit);
	    end // case: f1

	  c1:
	    begin
	       $display("c1: isn %0o ss %d, dd %d, no_op %d, ill %d, push %d, pop %d",
			isn, need_srcspec_dd, need_destspec_dd,
			no_operand, is_illegal, need_push_state, need_pop_reg);

	       $display("    need_src_data %d, need_dest_data %d",
			need_src_data, need_dest_data);

	       $display("   ss: mode%d reg%d ind%d post %d pre %d",
			ss_mode, ss_reg, ss_ea_ind,
			ss_post_incr, ss_pre_dec);


	       $display("   dd: mode%d reg%d ea %0o ind%d post %d pre %d",
			dd_mode, dd_reg, dd_ea, dd_ea_ind,
			dd_post_incr, dd_pre_dec);

	       $display("   need: dest_data %d; s1 %d, s2 %d, s4 %d; d1 %d, d2 %d, d4 %d", 
			need_dest_data,
			need_s1, need_s2, need_s4, need_d1, need_d2, need_d4);


	    end

	  s1:
	    begin
	       $display("s1:");
	    end
	  
	  s2:
	    begin
	       $display("s2: ss_ea_mux %0o, [ea]=%0o", ss_ea_mux, bus_data_in);
	    end

	  s3:
	    begin
	       $display("s3: ss_ea_mux %0o", ss_ea_mux);
	    end

	  s4:
	    begin
	       $display("s4: ss_ea_mux %0o, ss_data_mux %o, bus_data_in %o",
			ss_ea_mux, ss_data_mux, bus_data_in);
	    end

	  d1:
	    begin
	       $display("d1: dd_ea %0o, dd_ea_mux %0o", dd_ea, dd_ea_mux);
	       $display("    ss_data %0o, ss_data_mux %0o",
			ss_data, ss_data_mux);
	       
               if (dd_post_incr)
		 begin
		    $display(" R%d <- %o (dd r++)", dd_reg, dd_reg_value);
		 end
               else
		 if (dd_pre_dec)
		   begin
		      $display(" R%d <- %o (dd r--)", dd_reg, dd_reg_value);
		   end
	    end // case: d1
	  
	  d2:
	    begin
	       $display("d2: dd_ea %0o, dd_ea_mux %0o", dd_ea, dd_ea_mux);
	    end

	  d3:
	    begin
	       $display("d3:");
	    end

	  d4:
	    begin
	       $display("d4:");
	    end

	  e1:
	    begin
	       $display("e1: isn %o, ss_data %o, dd_data %o",
			isn, ss_data, dd_data);
	       $display("    e1_data_mux %o, e1_data %o", e1_data_mux, e1_data);

	       $display("    ss_data %0o, dd_data %0o, e1_result %0o",
			ss_data, dd_data, e1_result);
	       $display("    latch_pc %d, latch_cc %d, e1_advance %o",
			latch_pc, latch_cc, e1_advance);
	       $display("    psw %o", psw);

	       $display("    e1_result %o, e1_data %o, e1_data_mux %o",
			e1_result, e1_data, e1_data_mux);

	    end

	  w1:
	    begin
	       $display("w1: dd%d %d, dd_data %o, ss%d %d, ss_data %o, e1_data %o",
		      dd_mode, dd_reg, dd_data, ss_mode, ss_reg, ss_data, e1_data);
	       $display("    store_result %d, store_ss_reg %d, store_result32 %d",
			store_result, store_ss_reg, store_result32);
	       $display("    e1_data_mux %o, e1_data %o, e1_result %o",
			e1_data_mux, e1_data, e1_result);

	    end

	  o1:
	    begin
	       $display("o1:");
	    end

	  o2:
	    begin
	       $display("o2:");
	    end

	  o3:
	    begin
	       $display("o3:");
	    end


	  p1:
	    begin
	       $display("p1:");
	    end

	  t1:
	    begin
	       $display("t1: sp %o", sp);
	    end

	  t2:
	    begin
	       $display("t2:");
	    end

	  t3:
	    begin
	       $display("t3: ss_ea %o, ss_ea_mux %o", ss_ea, ss_ea_mux);
	    end

	  t4:
	    begin
	       $display("t4: ss_ea %o, ss_ea_mux %o", ss_ea, ss_ea_mux);
	    end

	  i1:
	    begin
	    end

	endcase // case(istate)

	if (istate == f1)
	  begin
	     $display("    regs %0o %0o %0o %0o ",
		      r0, r1, r2, r3);
	     $display("         %0o %0o %0o %0o ",
		      r4, r5, r6[current_mode], pc);
	     $display("         (sp %0o %0o %0o cm %d pm %d)",
		      r6[0], r6[1], r6[3], current_mode, previous_mode);

	  end

	if (istate == o1 || istate == o2 || istate == o3)
	     $display("    sp %0o", r6[current_mode]);
	
	$display("    bus rd=%d wr=%d addr %o data_out %o data_in %o",
		 bus_rd, bus_wr, bus_addr, bus_data_out, bus_data_in);

	$display("    ss_ea_mux %0o, ss_ea %0o, dd_ea_mux %0o, dd_ea %0o",
		 ss_ea_mux, ss_ea, dd_ea_mux, dd_ea);
	$display("    ss_data %0o, dd_data %0o",
		 ss_data, dd_data);
	  
     end

`endif
	    
endmodule


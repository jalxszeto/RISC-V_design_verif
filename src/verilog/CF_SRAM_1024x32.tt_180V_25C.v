
// ===============================================
// Copyright 2025, Umbralogic Technologies, LLC.
//
// Behavioral model of the 1024 x 32-bit SRAM macro used for instruction and data memory.

`timescale 1 ns / 1 ps
`define functional
`celldefine

module CF_SRAM_1024x32_macro
(DO, ScanOutCC, AD, BEN, CLKin, DI, EN, R_WB, ScanInCC, ScanInDL, ScanInDR, SM, TM, WLBI, WLOFF,
`ifdef USE_PG_PIN
vgnd, vnb, vpb, vpwra,
`endif
vpwrac,
`ifdef USE_PG_PIN
vpwrm,
vpwrp,
`endif
vpwrpc
);
    parameter NB = 32;  // Number of Data Bits
    parameter NA = 10;  // Number of Address Bits
    parameter NW = 1024;  // Number of WORDS
    parameter SEED = 0 ;    // User can define SEED at memory instantiation by .SEED(<Some_Seed_value>)

    output [(NB - 1) : 0] DO;
    output ScanOutCC;

    input [(NB - 1) : 0] DI;
    input [(NB - 1) : 0] BEN;
    input [(NA - 1) : 0] AD;
    input EN;
    input R_WB;
    input CLKin;
    input WLBI;
    input WLOFF;
    input TM;
    input SM;
    input ScanInCC;
    input ScanInDL;
    input ScanInDR;
    input vpwrac;
    input vpwrpc;
`ifdef USE_PG_PIN
    input vgnd;
    input vpwrm;

`ifdef CF_SRAM_PA_SIM
  inout vpwra;
`else
  input vpwra;
`endif


`ifdef CF_SRAM_PA_SIM
  inout vpwrp;
`else
  input vpwrp;
`endif

    input vnb;
    input vpb;
`else
    supply0 vgnd;
    supply0 vnb;
    supply1 vpwra;
    supply1 vpwrm;
    supply1 vpwrp;
    supply1 vpb;
`endif

    reg [(NB - 1) : 0] memory [0: (NW - 1)];

    wire undefined_mode ; 
    wire normal_mode ;
    wire test_mode ; 
    wire sleep_mode ; 
    wire pwroff_mode ;
    wire periphery_x_mode ;
    wire mem_x, write_mem_x ; 
    wire pg_cond ;

//Clock & Access Time Notify Registers
    reg notify_tCYC;
    reg notify_tCHI;
    reg notify_tCLO;
    reg notify_tRD;
    reg notify_tWR;

//Setup Time Notify Registers
    reg notify_tSDI;
    reg notify_tSA;
    reg notify_tSRWB;
    reg notify_tSBEN;
    reg notify_tSEN;
    reg notify_tSScanInCC;
    reg notify_tSScanInDL;
    reg notify_tSScanInDR;
    reg notify_tSSM;
    reg notify_tSTM;
    reg tsu_th_notifier_cond;
    reg tsu_th_notifier_cond_1;
    wire notifier_en;

// The variables below only used to initialize memory at zero time with random data
//-----------------------------------------------------------------------------------
    integer i, l ;
    reg [NA - 1 : 0] adr ;
    reg [NB - 1 : 0] din ;
    reg [NB:0] data_range;
//-----------------------------------------------------------------------------------
    reg EN_m ;  // State of the EN signal is saved when internal clock is 
    wire clki ;  // Internal clock signal 
    wire clki_tm ;  // Internal clock signal

    wire [(NB - 1) : 0] DO_temp ;
    wire ScanOutCC_temp ;
    wire tm_and_not_sm;

// The variables below are used for undefined state and write mem x messages.
    reg   msg_undef_is_pending       = 1'b0;
    reg   msg_undef_last_value       = 1'b0;
    time  msg_undef_pend_time;
    event msg_undef_pend_event;
    event msg_undef_process_event;
    reg   msg_write_x_is_pending     = 1'b0;
    reg   msg_write_x_last_value     = 1'b0;
    time  msg_write_x_pend_time;
    event msg_write_x_pend_event;
    event msg_write_x_process_event;

reg dis_err_msgs;
initial
begin
dis_err_msgs = 1'b1;
`ifdef CF_SRAM_DIS_ERR_MSGS
`else
#1;
dis_err_msgs = 1'b0;
`endif
end

    initial
    begin
    notify_tSDI= 1'b0;
    notify_tSA= 1'b0;
    notify_tSRWB= 1'b0;
    notify_tSBEN= 1'b0;
    notify_tSEN= 1'b0;
    notify_tSScanInCC= 1'b0;
    notify_tSScanInDL= 1'b0;
    notify_tSScanInDR= 1'b0;
    notify_tSSM= 1'b0;
    notify_tSTM= 1'b0;
    tsu_th_notifier_cond= 1'b0;
    tsu_th_notifier_cond_1= 1'b0;
    
   end
// determine when :
// (1) any input is 'z' or 'x' 
// (2) when there is any tsu/th violation on any of the inputs dlz   09/17/2011
// wire inputs_x = ^{AD, BEN, CLKin, EN, R_WB, ScanInCC, ScanInDL, ScanInDR, SM, TM, WLOFF};

   wire inputs_x = (WLOFF === 1) ?          1'b0 :
                (TM    === 1) ? ^{                 SM,                CLKin} :
                (EN    === 1) ? ^{WLOFF, TM, SM,     R_WB, BEN, CLKin} :
                (EN    === 0) ? ^{WLOFF, TM, SM,                CLKin} :
                                1'bx;
  wire scan_inputs_x = ^{ScanInCC, ScanInDL, ScanInDR};


    reg inputs_x_reg;
    wire scan_inputs_x_cond; 


// determine when :
// (1) any input is 'z' or 'x' 
// (2) when there is any tsu/th violation on any of the inputs dlz   09/17/2011


assign DO =( periphery_x_mode || tsu_th_notifier_cond ) ? {NB{1'bx}} : DO_temp ;

assign ScanOutCC = periphery_x_mode ? 1'bx : ScanOutCC_temp ;


// Following block determines if the control signals together
// presents an undefined condition. The logic for undefined 
// is given below.
// Warning message is thrown if undefiend condition is found.
// 
assign pg_cond= ((vpb===1'b1) && (vnb===1'b0) && (vgnd===1'b0)) ; 



   always @ (posedge CLKin) begin
     if (inputs_x === 1'bx) begin
         inputs_x_reg = 1'b1;
     end
     else begin
         inputs_x_reg = 1'b0;
    
     end
   end


// determine when 
// (1) any input is 'z' or 'x' 
// (2) when there is any tsu/th violation on any of the inputs dlz   09/17/2011

   assign scan_inputs_x_cond = (ScanInCC === 1'bz)||( ScanInDL === 1'bz)||(ScanInDR === 1'bz) ;


assign normal_mode=(vpwra===1 && vpwrp===1 && pg_cond && TM===0 && SM===0 && WLOFF===0 && tsu_th_notifier_cond===0);

assign test_mode  =(vpwrp===1 && pg_cond && TM===1 && tsu_th_notifier_cond===0);

assign sleep_mode =(vpwra===1 && pg_cond && WLOFF===1); 
// Deep sleep mode or Power Down 

assign undefined_mode = !(normal_mode || test_mode || sleep_mode || pwroff_mode) ;

assign pwroff_mode = (vpwra !== 1 && vpwrp !== 1 && pg_cond);
assign periphery_x_mode = (vpwrp !== 1);       
// Overlapped with poweroff mode/sleep mode conditions     

assign mem_x = ((vpwra !== 1) || (WLOFF=== 0 && vpwrp !== 1)) ;         

assign write_mem_x = (pwroff_mode || mem_x || undefined_mode || tsu_th_notifier_cond ) ;

always @ (notify_tSDI or notify_tSA or notify_tSRWB or notify_tSBEN or notify_tSEN) begin
  if (normal_mode || test_mode )
   begin
    disable TSU_TH_NOTIFIER_COND_CLEAR;
    tsu_th_notifier_cond = 1'b1;
   end
 end
always @ (posedge CLKin) begin: TSU_TH_NOTIFIER_COND_CLEAR
 #1 tsu_th_notifier_cond = 1'b0;
end



always @(notify_tSScanInCC) begin
  #1;
  memory_mode_inst.ADreg[11] <= 1'bx;
  memory_mode_inst.ADreg_scan[11] <= 'bx;
end

always @(notify_tSScanInDL) begin
  #1;
  memory_mode_inst.DIreg[0] <= 1'bx;
end

always @(notify_tSScanInDR) begin
  #1;
  memory_mode_inst.DIreg[NB/2] <= 1'bx;
end

always @(notify_tSA) begin
  #1;
  memory_mode_inst.ADreg <= 'bx;
  memory_mode_inst.ADreg_scan <= 'bx;
end

always @(notify_tSDI) begin
  #1;
  memory_mode_inst.DIreg <= 'bx;
end

always @(notify_tSRWB) begin
  #1;
  memory_mode_inst.R_WBreg_scan <= 'bx;
  memory_mode_inst.R_WBreg <= 'bx;
end

always @(notify_tSBEN) begin
  #1;
  memory_mode_inst.BENreg <= 'bx;
end

always @(notify_tSEN) begin
  #1;
  memory_mode_inst.ENreg <= 'bx;
  memory_mode_inst.ENreg_scan <= 'bx;
end

always @(notify_tSTM or notify_tSSM) begin
  #1;
  memory_mode_inst.DIreg <= 'bx;
  memory_mode_inst.ADreg <= 'bx;
  memory_mode_inst.ADreg_scan <= 'bx;
  memory_mode_inst.R_WBreg_scan <= 'bx;
  memory_mode_inst.R_WBreg <= 'bx;
  memory_mode_inst.BENreg <= 'bx;
  memory_mode_inst.ENreg <= 'bx;
  memory_mode_inst.ENreg_scan <= 'bx;
end

// Delay undefined state processing so that the final value of
// undefined mode from the originating time tick is available.
always @(msg_undef_pend_event) begin
    #1;
    -> msg_undef_process_event;
end

// Handle undefined state error queuing and processing.
always @(undefined_mode, msg_undef_process_event) begin
  #0.1;  


  // Display any pending undefined state errors from previous time ticks.
  // This must happen before processing signals from the current time tick.

  if (msg_undef_is_pending) begin
    if (msg_undef_pend_time != $time) begin
      msg_undef_is_pending = 1'b0;
      if (!dis_err_msgs) begin
        $display("===NOTE=== (efsram) : Undefined state in CF_SRAM_00128x032_008_18: vpwra= %b vpwrp=%b TM=%b SM=%b WLOFF=%b in instance %m at time=%t", vpwrac, vpwrpc, TM, SM, WLOFF, $time) ;
      end
    end
  end

  // Process signals in the current time tick.
  // This code may be executed more than once per time tick.
  if (undefined_mode) begin
    // Only queue an error message on a change in undefined_mode
    if (msg_undef_last_value == 1'b0) begin
      msg_undef_is_pending = 1'b1;
      msg_undef_pend_time = $time;
      -> msg_undef_pend_event;
    end
  end
  else begin
    // Clear any pending undefined mode error messages.
    msg_undef_is_pending = 1'b0;
  end

  msg_undef_last_value = undefined_mode;
end

// Delay write mem x processing so that the final value of
// write mem x from the originating time tick is available.
always @(msg_write_x_pend_event) begin
    #1;
    -> msg_write_x_process_event;
end

// Handle write_mem_x action queuing and processing.
always @(write_mem_x, dis_err_msgs, msg_write_x_process_event) begin

  // Handle any pending write mem Xs from previous time ticks.
  // This must happen before processing signals from the current time tick.
  if (msg_write_x_is_pending) begin
    if (msg_write_x_pend_time != $time) begin
      msg_write_x_is_pending = 1'b0;
      #0.1;
      if(write_mem_x) begin
        write_x_in_whole_memory;
        if (!dis_err_msgs) begin
          $display("===INFO=== (cftssc) : Writing X to whole memory:pwroff_mode=%b mem_x=%b undefined_mode=%b in instance %m at %t",pwroff_mode, mem_x, undefined_mode, $time) ;
        end
      end
      #0.1;
    end
  end

  // Process signals in the current time tick.
  // This code may be executed more than once per time tick.
  if (write_mem_x) begin
    // Only queue an error message on a change in write_mem_x
    if (msg_write_x_last_value == 1'b0) begin
      msg_write_x_is_pending = 1'b1;
      msg_write_x_pend_time = $time;
      -> msg_write_x_pend_event;
    end
  end
  else begin
    // Clear any pending write mem x actions.
    msg_write_x_is_pending = 1'b0;
  end
  msg_write_x_last_value = write_mem_x;
end

assign notifier_en = (EN===1'b1) && (sleep_mode !== 1'b1) && (pwroff_mode !== 1'b1) && (periphery_x_mode !== 1'b1) && (mem_x !== 1'b1) && (undefined_mode !== 1'b1) ;


//===================================================================================
//  Clock Gating functionality:
//    When the macro is deselected with EN = 0, internal clock gating 
//    doesn't affect the external operations of the macro.
//    When EN = 0 and macro is not in test mode i.e. SM = TM = 0 
//    the clock path of the macro is forced to an inactive state i.e. clki = 0  
//===================================================================================

    always @(*) begin
        #0.1;
        if (CLKin == 0)
            EN_m = EN;
    end  

    assign clki = CLKin && (EN_m || TM || SM); // Clock Gating logic
    assign clki_tm = CLKin && (TM || SM); // Clocking logic for test mode


    //WorkAround provided by MGC -BOH 
    and i1 (tm_and_not_sm, TM, !SM);

   wire not_tm_and_notifier_en = TM===1'b0 && notifier_en===1'b1;
   wire tm_and_not_sm_and_notifier_en = tm_and_not_sm && notifier_en===1'b1;
   wire not_sm_and_notifier_en = SM===1'b0 && notifier_en===1'b1;
   wire sm_and_notifier_en = SM===1'b1 && notifier_en===1'b1;
   wire notifier_en_a = notifier_en===1'b1; 


// dlz compute signals for the timing notifiers CDT 108028 

// This block to initialize the memory array with random data at zero time. 
// If the input SEED is zero then default memory contents is 'x'.
// To initialize with random 1/0 user need to 
initial begin
    rand_init_whole_memory ;
end

`ifndef functional

specify
    specparam

    tCYC = 8.0000,
    tCHI = 4.0000,
    tCLO = 4.0000,
    tRD = 2.4412,
    tWR = 2.0412,
    tTD = 1.6212,
    tTM = 1.7481,
    tSSM = 6.5000,
    tHSM = 1.0000,
    tSTM = 6.5000,
    tHTM = 1.0000,
    tSADCTL = 0.8000,
    tHADCTL = 0.5500,
    tSASSC = 0.5500,
    tDASSC = 1.0000,
    tSA0 = 0.5000,  
    tHA0 = 0.3300,  
    tSA1 = 0.5000,  
    tHA1 = 0.3300,  
    tSA2 = 0.5000,  
    tHA2 = 0.3300,  
    tSA3 = 0.5000,  
    tHA3 = 0.3300,  
    tSA4 = 0.5000,  
    tHA4 = 0.3300,  
    tSA5 = 0.5000,  
    tHA5 = 0.3300,  
    tSA6 = 0.5000,  
    tHA6 = 0.3300,  
    tSA7 = 0.5000,  
    tHA7 = 0.3300,  
    tSA8 = 0.5000,  
    tHA8 = 0.3300,  
    tSA9 = 0.5000,  
    tHA9 = 0.3300,  
    tSDI0 = 0.7000,  
    tHDI0 = 0.5400, 
    tSDI1 = 0.7000,  
    tHDI1 = 0.5400, 
    tSDI2 = 0.7000,  
    tHDI2 = 0.5400, 
    tSDI3 = 0.7000,  
    tHDI3 = 0.5400, 
    tSDI4 = 0.7000,  
    tHDI4 = 0.5400, 
    tSDI5 = 0.7000,  
    tHDI5 = 0.5400, 
    tSDI6 = 0.7000,  
    tHDI6 = 0.5400, 
    tSDI7 = 0.7000,  
    tHDI7 = 0.5400, 
    tSDI8 = 0.7000,  
    tHDI8 = 0.5400, 
    tSDI9 = 0.7000,  
    tHDI9 = 0.5400, 
    tSDI10 = 0.7000,  
    tHDI10 = 0.5400, 
    tSDI11 = 0.7000,  
    tHDI11 = 0.5400, 
    tSDI12 = 0.7000,  
    tHDI12 = 0.5400, 
    tSDI13 = 0.7000,  
    tHDI13 = 0.5400, 
    tSDI14 = 0.7000,  
    tHDI14 = 0.5400, 
    tSDI15 = 0.7000,  
    tHDI15 = 0.5400, 
    tSDI16 = 0.7000,  
    tHDI16 = 0.5400, 
    tSDI17 = 0.7000,  
    tHDI17 = 0.5400, 
    tSDI18 = 0.7000,  
    tHDI18 = 0.5400, 
    tSDI19 = 0.7000,  
    tHDI19 = 0.5400, 
    tSDI20 = 0.7000,  
    tHDI20 = 0.5400, 
    tSDI21 = 0.7000,  
    tHDI21 = 0.5400, 
    tSDI22 = 0.7000,  
    tHDI22 = 0.5400, 
    tSDI23 = 0.7000,  
    tHDI23 = 0.5400, 
    tSDI24 = 0.7000,  
    tHDI24 = 0.5400, 
    tSDI25 = 0.7000,  
    tHDI25 = 0.5400, 
    tSDI26 = 0.7000,  
    tHDI26 = 0.5400, 
    tSDI27 = 0.7000,  
    tHDI27 = 0.5400, 
    tSDI28 = 0.7000,  
    tHDI28 = 0.5400, 
    tSDI29 = 0.7000,  
    tHDI29 = 0.5400, 
    tSDI30 = 0.7000,  
    tHDI30 = 0.5400, 
    tSDI31 = 0.7000,  
    tHDI31 = 0.5400, 
    tSBEN = 0.7000,  
    tHBEN = 0.5400,  
    tSEN = 1.3000,  
    tHEN = 0.4300,  
    tSRWB = 0.5000,  
    tHRWB = 0.3300; 


    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[0]:DI[0])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[1]:DI[1])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[2]:DI[2])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[3]:DI[3])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[4]:DI[4])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[5]:DI[5])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[6]:DI[6])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[7]:DI[7])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[8]:DI[8])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[9]:DI[9])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[10]:DI[10])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[11]:DI[11])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[12]:DI[12])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[13]:DI[13])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[14]:DI[14])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[15]:DI[15])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[16]:DI[16])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[17]:DI[17])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[18]:DI[18])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[19]:DI[19])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[20]:DI[20])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[21]:DI[21])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[22]:DI[22])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[23]:DI[23])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[24]:DI[24])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[25]:DI[25])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[26]:DI[26])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[27]:DI[27])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[28]:DI[28])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[29]:DI[29])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[30]:DI[30])) = (tWR,0); 
    if(((EN & (!R_WB)) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[31]:DI[31])) = (tWR,0); 

    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[0]:DI[0])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[1]:DI[1])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[2]:DI[2])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[3]:DI[3])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[4]:DI[4])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[5]:DI[5])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[6]:DI[6])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[7]:DI[7])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[8]:DI[8])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[9]:DI[9])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[10]:DI[10])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[11]:DI[11])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[12]:DI[12])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[13]:DI[13])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[14]:DI[14])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[15]:DI[15])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[16]:DI[16])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[17]:DI[17])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[18]:DI[18])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[19]:DI[19])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[20]:DI[20])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[21]:DI[21])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[22]:DI[22])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[23]:DI[23])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[24]:DI[24])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[25]:DI[25])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[26]:DI[26])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[27]:DI[27])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[28]:DI[28])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[29]:DI[29])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[30]:DI[30])) = (tRD,0); 
    if(((EN & R_WB) & (!WLOFF)) & (!TM)) (posedge CLKin *> (DO[31]:DI[31])) = (tRD,0); 

    if(TM)
    	(posedge CLKin => (ScanOutCC:ScanInCC)) = (tTM,0); 


    if (TM) (posedge CLKin *> (DO[0]:DI[0])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[1]:DI[1])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[2]:DI[2])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[3]:DI[3])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[4]:DI[4])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[5]:DI[5])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[6]:DI[6])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[7]:DI[7])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[8]:DI[8])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[9]:DI[9])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[10]:DI[10])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[11]:DI[11])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[12]:DI[12])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[13]:DI[13])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[14]:DI[14])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[15]:DI[15])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[16]:DI[16])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[17]:DI[17])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[18]:DI[18])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[19]:DI[19])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[20]:DI[20])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[21]:DI[21])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[22]:DI[22])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[23]:DI[23])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[24]:DI[24])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[25]:DI[25])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[26]:DI[26])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[27]:DI[27])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[28]:DI[28])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[29]:DI[29])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[30]:DI[30])) = (tTD,0); 
    if (TM) (posedge CLKin *> (DO[31]:DI[31])) = (tTD,0); 

    $width( posedge CLKin, tCHI, 0, notify_tCHI);
    $width( negedge CLKin, tCLO, 0, notify_tCLO);
    $period( posedge CLKin, tCYC, notify_tCYC);



$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[0], tSA0, tHA0, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[0], tSA0, tHA0, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[0],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[0],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[1], tSA1, tHA1, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[1], tSA1, tHA1, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[1],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[1],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[2], tSA2, tHA2, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[2], tSA2, tHA2, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[2],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[2],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[3], tSA3, tHA3, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[3], tSA3, tHA3, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[3],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[3],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[4], tSA4, tHA4, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[4], tSA4, tHA4, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[4],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[4],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[5], tSA5, tHA5, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[5], tSA5, tHA5, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[5],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[5],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[6], tSA6, tHA6, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[6], tSA6, tHA6, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[6],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[6],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[7], tSA7, tHA7, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[7], tSA7, tHA7, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[7],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[7],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[8], tSA8, tHA8, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[8], tSA8, tHA8, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[8],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[8],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge AD[9], tSA9, tHA9, notify_tSA,,,,); 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge AD[9], tSA9, tHA9, notify_tSA,,,,); 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge AD[9],tSADCTL,tHADCTL,notify_tSA,,,,); 
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge AD[9],tSADCTL,tHADCTL,notify_tSA,,,,); 


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[0], tSDI0, tHDI0, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[0], tSDI0, tHDI0, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[1], tSDI1, tHDI1, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[1], tSDI1, tHDI1, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[2], tSDI2, tHDI2, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[2], tSDI2, tHDI2, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[3], tSDI3, tHDI3, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[3], tSDI3, tHDI3, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[4], tSDI4, tHDI4, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[4], tSDI4, tHDI4, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[5], tSDI5, tHDI5, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[5], tSDI5, tHDI5, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[6], tSDI6, tHDI6, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[6], tSDI6, tHDI6, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[7], tSDI7, tHDI7, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[7], tSDI7, tHDI7, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[8], tSDI8, tHDI8, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[8], tSDI8, tHDI8, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[9], tSDI9, tHDI9, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[9], tSDI9, tHDI9, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[10], tSDI10, tHDI10, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[10], tSDI10, tHDI10, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[11], tSDI11, tHDI11, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[11], tSDI11, tHDI11, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[12], tSDI12, tHDI12, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[12], tSDI12, tHDI12, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[13], tSDI13, tHDI13, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[13], tSDI13, tHDI13, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[14], tSDI14, tHDI14, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[14], tSDI14, tHDI14, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[15], tSDI15, tHDI15, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[15], tSDI15, tHDI15, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[16], tSDI16, tHDI16, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[16], tSDI16, tHDI16, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[17], tSDI17, tHDI17, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[17], tSDI17, tHDI17, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[18], tSDI18, tHDI18, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[18], tSDI18, tHDI18, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[19], tSDI19, tHDI19, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[19], tSDI19, tHDI19, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[20], tSDI20, tHDI20, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[20], tSDI20, tHDI20, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[21], tSDI21, tHDI21, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[21], tSDI21, tHDI21, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[22], tSDI22, tHDI22, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[22], tSDI22, tHDI22, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[23], tSDI23, tHDI23, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[23], tSDI23, tHDI23, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[24], tSDI24, tHDI24, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[24], tSDI24, tHDI24, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[25], tSDI25, tHDI25, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[25], tSDI25, tHDI25, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[26], tSDI26, tHDI26, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[26], tSDI26, tHDI26, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[27], tSDI27, tHDI27, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[27], tSDI27, tHDI27, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[28], tSDI28, tHDI28, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[28], tSDI28, tHDI28, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[29], tSDI29, tHDI29, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[29], tSDI29, tHDI29, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[30], tSDI30, tHDI30, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[30], tSDI30, tHDI30, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_sm_and_notifier_en, posedge DI[31], tSDI31, tHDI31, notify_tSDI,,,,); 
$setuphold(posedge CLKin &&& not_sm_and_notifier_en, negedge DI[31], tSDI31, tHDI31, notify_tSDI,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[0], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[0], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[0],tSDI0,tHDI0,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[0],tSDI0,tHDI0,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[1], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[1], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[1],tSDI1,tHDI1,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[1],tSDI1,tHDI1,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[2], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[2], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[2],tSDI2,tHDI2,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[2],tSDI2,tHDI2,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[3], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[3], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[3],tSDI3,tHDI3,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[3],tSDI3,tHDI3,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[4], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[4], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[4],tSDI4,tHDI4,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[4],tSDI4,tHDI4,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[5], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[5], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[5],tSDI5,tHDI5,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[5],tSDI5,tHDI5,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[6], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[6], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[6],tSDI6,tHDI6,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[6],tSDI6,tHDI6,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[7], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[7], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[7],tSDI7,tHDI7,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[7],tSDI7,tHDI7,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[8], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[8], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[8],tSDI8,tHDI8,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[8],tSDI8,tHDI8,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[9], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[9], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[9],tSDI9,tHDI9,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[9],tSDI9,tHDI9,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[10], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[10], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[10],tSDI10,tHDI10,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[10],tSDI10,tHDI10,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[11], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[11], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[11],tSDI11,tHDI11,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[11],tSDI11,tHDI11,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[12], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[12], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[12],tSDI12,tHDI12,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[12],tSDI12,tHDI12,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[13], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[13], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[13],tSDI13,tHDI13,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[13],tSDI13,tHDI13,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[14], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[14], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[14],tSDI14,tHDI14,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[14],tSDI14,tHDI14,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[15], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[15], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[15],tSDI15,tHDI15,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[15],tSDI15,tHDI15,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[16], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[16], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[16],tSDI16,tHDI16,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[16],tSDI16,tHDI16,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[17], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[17], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[17],tSDI17,tHDI17,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[17],tSDI17,tHDI17,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[18], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[18], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[18],tSDI18,tHDI18,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[18],tSDI18,tHDI18,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[19], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[19], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[19],tSDI19,tHDI19,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[19],tSDI19,tHDI19,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[20], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[20], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[20],tSDI20,tHDI20,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[20],tSDI20,tHDI20,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[21], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[21], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[21],tSDI21,tHDI21,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[21],tSDI21,tHDI21,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[22], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[22], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[22],tSDI22,tHDI22,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[22],tSDI22,tHDI22,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[23], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[23], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[23],tSDI23,tHDI23,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[23],tSDI23,tHDI23,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[24], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[24], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[24],tSDI24,tHDI24,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[24],tSDI24,tHDI24,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[25], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[25], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[25],tSDI25,tHDI25,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[25],tSDI25,tHDI25,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[26], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[26], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[26],tSDI26,tHDI26,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[26],tSDI26,tHDI26,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[27], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[27], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[27],tSDI27,tHDI27,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[27],tSDI27,tHDI27,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[28], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[28], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[28],tSDI28,tHDI28,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[28],tSDI28,tHDI28,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[29], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[29], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[29],tSDI29,tHDI29,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[29],tSDI29,tHDI29,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[30], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[30], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[30],tSDI30,tHDI30,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[30],tSDI30,tHDI30,notify_tSBEN,,,,);


$setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge BEN[31], tSBEN, tHBEN, notify_tSBEN,,,,) ; 
$setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge BEN[31], tSBEN, tHBEN, notify_tSBEN,,,,) ; 

$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge BEN[31],tSDI31,tHDI31,notify_tSBEN,,,,);
$setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge BEN[31],tSDI31,tHDI31,notify_tSBEN,,,,);


    $setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge EN, tSEN, tHEN, notify_tSEN,,,,) ; 
    $setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge EN, tSEN, tHEN, notify_tSEN,,,,) ; 

    $setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge EN, tSADCTL, tHADCTL, notify_tSEN,,,,) ;
    $setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge EN, tSADCTL, tHADCTL, notify_tSEN,,,,) ;

    $setuphold(posedge CLKin &&& notifier_en_a, posedge SM, tSSM, tHSM, notify_tSSM,,,,) ; 
    $setuphold(posedge CLKin &&& notifier_en_a, negedge SM, tSSM, tHSM, notify_tSSM,,,,) ;

    $setuphold(posedge CLKin &&& notifier_en_a, posedge TM, tSTM, tHTM, notify_tSTM,,,,) ; 
    $setuphold(posedge CLKin &&& notifier_en_a, negedge TM, tSTM, tHTM, notify_tSTM,,,,) ;

    $setuphold(posedge CLKin &&& not_tm_and_notifier_en, posedge R_WB, tSRWB, tHRWB, notify_tSRWB,,,,) ; 
    $setuphold(posedge CLKin &&& not_tm_and_notifier_en, negedge R_WB, tSRWB, tHRWB, notify_tSRWB,,,,) ; 

    $setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, posedge R_WB, tSADCTL, tHADCTL, notify_tSRWB,,,,) ;
    $setuphold(posedge CLKin &&& tm_and_not_sm_and_notifier_en, negedge R_WB, tSADCTL, tHADCTL, notify_tSRWB,,,,) ;

    $setuphold(posedge CLKin &&& sm_and_notifier_en, posedge ScanInCC, tSADCTL, tHADCTL, notify_tSScanInCC,,,,) ; 
    $setuphold(posedge CLKin &&& sm_and_notifier_en, negedge ScanInCC, tSADCTL, tHADCTL, notify_tSScanInCC,,,,) ;

    $setuphold(posedge CLKin &&& sm_and_notifier_en, posedge ScanInDL, tSASSC, tDASSC, notify_tSScanInDL,,,,) ; 
    $setuphold(posedge CLKin &&& sm_and_notifier_en, negedge ScanInDL, tSASSC, tDASSC, notify_tSScanInDL,,,,) ;

    $setuphold(posedge CLKin &&& sm_and_notifier_en, posedge ScanInDR, tSASSC, tDASSC, notify_tSScanInDR,,,,) ; 
    $setuphold(posedge CLKin &&& sm_and_notifier_en, negedge ScanInDR, tSASSC, tDASSC, notify_tSScanInDR,,,,) ;


endspecify

`endif


    // Property of Control signals: vpwrac, vpwrpc
    bufif0 (vpwra, vpwrm, vpwrac) ; // if vpwrac is low, signal vpwra is connected to vpwrm 
    bufif0 (vpwrp, vpwrm, vpwrpc) ; // if vpwrpc is low, signal vpwrp is connected to vpwrm


CF_SRAM_1024x32_memory_mode memory_mode_inst(DO_temp, ScanOutCC_temp, normal_mode, test_mode, periphery_x_mode, clki, clki_tm,
AD, BEN, DI, EN, EN_m, R_WB, SM, ScanInCC, ScanInDL, ScanInDR, WLOFF, vgnd, dis_err_msgs, inputs_x_reg);

task write_x_in_whole_memory;
integer k;
begin
    for (k = 0; k < NW; k = k + 1)
        memory_mode_inst.memory[k] = 32'bx;
end
endtask

task rand_init_whole_memory;
integer l ;
begin
    l = SEED ;
    if (l > 0) begin 
        for (i = 0; i < NB; i = i + 1) 
            data_range[i] = 1'b0;
        data_range[NB] = 1'b1;
        for( i = 0 ; i < NW ; i = i + 1) begin
            adr = {i} % NW;
            din = ($random(l)+1) % data_range ;
            memory_mode_inst.memory[adr] = din ;
        end
    end 
end
endtask


endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// This module is for normal memory mode operations Read/Write
// A 2D memory array 'memory' is defined in this module.
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module CF_SRAM_1024x32_memory_mode (DO, ScanOutCC, normal_mode, test_mode, periphery_x_mode, clki, clki_tm,
                                   AD, BEN, DI, EN, EN_m, R_WB, SM, ScanInCC, ScanInDL, ScanInDR, WLOFF, vgnd, dis_err_msgs, inputs_x_reg); // dlz added dis_err_msgs BMRB request
    parameter NB = 32;         // Number of Data Bits
    parameter NA = 10;         // Number of Address Bits
    parameter NW = 1024;         // Number of WORDS

    parameter tRD = 2.4412;  // Read access time for the memory (i.e. delay for DI to DO change in Read)
    parameter tWR = 2.0412;  //Write access time for the memory (i.e. delay for DI to DO change in Write)

    parameter tWRDL = 0.1 ;
    // delay the Write to avoid simulataneous switching of R_WBreg from Write to Read opeartion
    parameter BEHAV_DELAY = 0.1;

    output [(NB - 1) : 0] DO;
    output ScanOutCC ;
    input normal_mode ;
    input test_mode ;
    input periphery_x_mode ;
    input dis_err_msgs;
    input clki;             // Gated Clock
    input clki_tm;          // Gated Clock for test mode
                                    
    input [(NA - 1) : 0] AD;
    input [(NB - 1) : 0] BEN;
    input [(NB - 1) : 0] DI;
    input EN;
    input EN_m;
    input R_WB;
    input SM ; 
    input ScanInCC;
    input ScanInDL;
    input ScanInDR;
    input WLOFF ;
    input vgnd;
    input inputs_x_reg;

    reg [12 - 1: 0] ADreg;          // ADreg bits holds AD bits in synchronously
    reg [12 - 1: 0] ADreg_scan;     // ADreg_scan bits holds AD bits in scan mode
    reg [12 - 1: 0] ADreg_scan_1;   // ADreg_scan bits holds AD bits in scan mode // dlz 09/09/2011
    reg [NB - 1: 0] DIreg;          // DIreg bits holds DI bits in synchronously
    reg [NB - 1: 0] DOreg;          // Sense Amplifier output
    reg [NB - 1: 0] DI_BENreg ;     // This register contains DI data after masking by BEN bits
    reg [NB - 1: 0] BENreg;         // BENreg holds BEN data synchronously
    
    reg  [(NB - 1) : 0] memory [0: (NW - 1)];

    reg WL_Enable;                  // reg for Word Line enable signal. 
    reg ENreg;                      // reg for Chip Enable 
    reg R_WBreg ;                   // reg for Read/Write Enable signal
    reg WLOFFreg ;                  // reg to hold value of WLOFF in Scan chain

    reg ENreg_scan ;                // reg for Chip Enable 
    reg R_WBreg_scan ;              // reg for Read/Write Enable signal
    reg WLOFFreg_scan ;             // reg to hold value of WLOFF in Scan chain

                                    // Functional Mode: 
                                    //    DO is DOreg when R_WBreg is Read state and persists
                                    //    DO is DIreg when R_WBreg is Write state and persists  
    reg [NB - 1: 0] DO_delay ;

// Scan mode/Test mode related registers
    wire ScanOutA ;
    wire [NB - 1:0] DImux1 ; 
    wire [12 - 1:0] ADmux ;  
    wire [NB - 1:0] DImux2 ; 
    wire R_WBmux ;  
    wire WLOFFmux ;  
    wire ENmux ; 

    assign DO = normal_mode ? DO_delay : (test_mode? DIreg : 32'bx) ;

    assign ScanOutCC = normal_mode ? 1'b1 : (test_mode? !(ENreg_scan): 1'bx) ;

    integer k, flag ;

//-----------------------------------------------------------------------------------
// The following block implements the DFT - scan chain for SRAM memory
// The Address scan chain is of length 15.
// Address scan chain is given below:
//  ScanInCC-->ADmux[11]-->ADreg_scan[11]-->ADmux[10]-->ADreg_scan[10]-->ADmux[9]-->ADreg_scan[9] 
//          -->ADmux[8]-->ADreg_scan[8] ...... -->ADmux[0]-->ADreg_scan[0]-->R_WBmux-->R_WBreg
//          -->WLOFFmux-->WLOFFreg-->ENmux-->ENreg-->ScanOutCC
//-----------------------------------------------------------------------------------

    assign #(BEHAV_DELAY) ADmux[0] = (SM) ? ADreg_scan[1] : AD[0] ;
    assign #(BEHAV_DELAY) ADmux[1] = (SM) ? ADreg_scan[2] : AD[1] ;
    assign #(BEHAV_DELAY) ADmux[2] = (SM) ? ADreg_scan[3] : AD[2] ;
    assign #(BEHAV_DELAY) ADmux[3] = (SM) ? ADreg_scan[4] : vgnd ;
    assign #(BEHAV_DELAY) ADmux[4] = (SM) ? ADreg_scan[5] : vgnd ;
    assign #(BEHAV_DELAY) ADmux[5] = (SM) ? ADreg_scan[6] : AD[4] ;
    assign #(BEHAV_DELAY) ADmux[6] = (SM) ? ADreg_scan[7] : AD[5] ;
    assign #(BEHAV_DELAY) ADmux[7] = (SM) ? ADreg_scan[8] : AD[6] ;
    assign #(BEHAV_DELAY) ADmux[8] = (SM) ? ADreg_scan[9] : AD[7] ;
    assign #(BEHAV_DELAY) ADmux[9] = (SM) ? ADreg_scan[10] : AD[8] ;
    assign #(BEHAV_DELAY) ADmux[10] = (SM) ? ADreg_scan[11] : AD[9] ;


assign #(BEHAV_DELAY) ADmux[11] = (SM) ? ((ScanInCC===1'bz)?1'bx:ScanInCC) : AD[3];

    assign #(BEHAV_DELAY) R_WBmux = (SM) ? ADreg_scan[0] : R_WB ;
    assign #(BEHAV_DELAY) WLOFFmux = (SM) ? R_WBreg_scan : WLOFF ; 
    assign #(BEHAV_DELAY) ENmux = (SM) ? WLOFFreg_scan : EN ; 
   
    // Depending on ScanOutA DI or BEN is used in Data Scan chains
    assign ScanOutA = test_mode ? !(ADreg_scan[0]) : 1'b1 ;

    // This block defines the two Data scan chains:-
    // Left Data Scan chain: entry is ScanInDL, size is 32/2  
    // Right Data Scan chain: entry is ScanInDR, size is (NB - 32/2) 
    assign #(BEHAV_DELAY) DImux1 = ScanOutA ? DI: BEN ;


assign #(BEHAV_DELAY) DImux2[0] = (SM) ? ((ScanInDL===1'bz)?1'bx:ScanInDL) : DImux1[0] ;   

    assign DImux2[1] = (SM) ? DIreg[0] : DImux1[1] ;
    assign DImux2[2] = (SM) ? DIreg[1] : DImux1[2] ;
    assign DImux2[3] = (SM) ? DIreg[2] : DImux1[3] ;
    assign DImux2[4] = (SM) ? DIreg[3] : DImux1[4] ;
    assign DImux2[5] = (SM) ? DIreg[4] : DImux1[5] ;
    assign DImux2[6] = (SM) ? DIreg[5] : DImux1[6] ;
    assign DImux2[7] = (SM) ? DIreg[6] : DImux1[7] ;
    assign DImux2[8] = (SM) ? DIreg[7] : DImux1[8] ;
    assign DImux2[9] = (SM) ? DIreg[8] : DImux1[9] ;
    assign DImux2[10] = (SM) ? DIreg[9] : DImux1[10] ;
    assign DImux2[11] = (SM) ? DIreg[10] : DImux1[11] ;
    assign DImux2[12] = (SM) ? DIreg[11] : DImux1[12] ;
    assign DImux2[13] = (SM) ? DIreg[12] : DImux1[13] ;
    assign DImux2[14] = (SM) ? DIreg[13] : DImux1[14] ;
    assign DImux2[15] = (SM) ? DIreg[14] : DImux1[15] ;


assign #(BEHAV_DELAY) DImux2[16] = (SM) ? ((ScanInDR===1'bz)?1'bx:ScanInDR) : DImux1[16] ;  

    assign DImux2[17] = (SM) ? DIreg[16] : DImux1[17] ;
    assign DImux2[18] = (SM) ? DIreg[17] : DImux1[18] ;
    assign DImux2[19] = (SM) ? DIreg[18] : DImux1[19] ;
    assign DImux2[20] = (SM) ? DIreg[19] : DImux1[20] ;
    assign DImux2[21] = (SM) ? DIreg[20] : DImux1[21] ;
    assign DImux2[22] = (SM) ? DIreg[21] : DImux1[22] ;
    assign DImux2[23] = (SM) ? DIreg[22] : DImux1[23] ;
    assign DImux2[24] = (SM) ? DIreg[23] : DImux1[24] ;
    assign DImux2[25] = (SM) ? DIreg[24] : DImux1[25] ;
    assign DImux2[26] = (SM) ? DIreg[25] : DImux1[26] ;
    assign DImux2[27] = (SM) ? DIreg[26] : DImux1[27] ;
    assign DImux2[28] = (SM) ? DIreg[27] : DImux1[28] ;
    assign DImux2[29] = (SM) ? DIreg[28] : DImux1[29] ;
    assign DImux2[30] = (SM) ? DIreg[29] : DImux1[30] ;
    assign DImux2[31] = (SM) ? DIreg[30] : DImux1[31] ;

   // In behavioral mode output DO signal to be delayed 
   // by (tRD/tWR) when in Read/Write mode
   // DO_delay is the delayed output to be set to DO.
    always @(normal_mode or DOreg or R_WBreg or WL_Enable) begin
        if (normal_mode && WL_Enable) begin 
`ifdef functional
            DO_delay <= DOreg;
`else
            DO_delay <= #((R_WBreg == 1) ? tRD: tWR) DOreg; 
            // Signal delayed for behavioral mode
`endif
        end
    end
 // At every positive edge of the clock the Synchronous input 
 // signals are saved into the corresponding register variable
 // All ADreg is of range [12 : 0], all ADreg signal is not 
 // assigned by AD. Depending upon memory configuration some
 // ADreg bit will be grounded. The index for grounded ADreg
 // bits are obtained following a scheme (memo PAI-046) 

    always @ (posedge clki) begin
        if (!periphery_x_mode && !test_mode) begin 
            DIreg <= DImux2 ;
            ADreg <= ADmux ;

            ADreg_scan_1 <= ADmux ;
            ADreg_scan <= ADreg_scan_1;

            ENreg <= ENmux ;
            WL_Enable <= EN_m ;
            R_WBreg <= R_WBmux ;
            WLOFFreg <= WLOFFmux;
            BENreg <= BEN ; 
            is_Floating_Signal(ENreg, DIreg, BENreg, ADreg) ;
        end
   end

   // During periphery_x_mode:  clki is gated
   always @ (periphery_x_mode) begin
        #0.1;
        if (periphery_x_mode == 1) begin 
            DIreg <= 32'bx ;
            ADreg <= 12'bx ;
            ADreg_scan <= 12'bx ;
            ENreg <= 1'bx ;
            R_WBreg <= 1'bx ;
            WLOFFreg <= 1'bx;
            ENreg_scan <= 1'bx ;
            R_WBreg_scan <= 1'bx ;
            WLOFFreg_scan <= 1'bx;
            BENreg <= 32'bx ; 
            DOreg  <= 32'bx ;
            WL_Enable <= 1'bx ;
        end
    end


/////////////////////////////////////////////////////////////////////////////////////////
// Test mode clocking is different than normal mode
//
    always @ (posedge clki_tm) begin
        if (test_mode) begin 
            DIreg <= DImux2 ;
            ADreg_scan <= ADmux ;   
            ENreg_scan <= ENmux ;
            R_WBreg_scan <= R_WBmux ;
            WLOFFreg_scan <= WLOFFmux;
            BENreg <= BEN ; 
            is_Floating_Signal(ENreg_scan, DIreg, BENreg, ADreg_scan) ;
        end
    end

/////////////////////////////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////////////////////////////
// This block does the following in Write mode:
//    (1) Write into memory array at Address ADreg
//    (2) Updates DOreg with DIreg value (flow-through)
//    (3) Check if the address AD is valid address
// The Bit enable signals can be used to write into individual bit of a memory word. 
// If not Bit enable signal is high, memory contents and DO doesn't change    
/////////////////////////////////////////////////////////////////////////////////////////

always @ (normal_mode or DIreg or R_WBreg or WL_Enable or ADreg or BENreg or WLOFFreg or dis_err_msgs or inputs_x_reg)
 begin: write_data_block
  if(normal_mode && WL_Enable && (!R_WBreg) && (!WLOFFreg)) begin
    #(tWRDL) ; 
	  if (is_AD_x(getAD(ADreg)) == 1) begin

      write_x_in_whole_memory;
    end 
    else if (is_AD_within_range(getAD(ADreg)) == 0) begin
      if (!dis_err_msgs) begin
		    $display("===ERROR=== (cftssc) : Write AD=%h OutOfRange in memory S8TSSC_01024x032_008_18 in instance %m at time=%t\n", ADreg, $time);
      end
    end
    else if (inputs_x_reg === 1'b1) begin
      DOreg = {NB{1'bx}};
    end
    else begin
      flag = 0 ;
      DI_BENreg = memory[getAD(ADreg)];
      for (k = 0 ; k < NB ; k = k + 1) begin
        if(BENreg[k] == 1) begin 
          if (DIreg[k] === 1'bz) begin  
            DI_BENreg[k] = 1'bx ;
            DOreg[k] = 1'bx ; 
          end                           
          else begin
            DI_BENreg[k] = DIreg[k] ;
            DOreg[k] = DIreg[k] ; 
            flag = 1 ;
          end
        end
        else if (BENreg[k] === 1'bx) begin 
          DI_BENreg[k] = 1'bx;
          DOreg[k] = 1'bx;
          flag = 1 ;  
        end
      end
      if (flag == 1) begin
        memory[getAD(ADreg)] = DI_BENreg ;
      end
    end
  end
end

 // This block does the following in Read mode:
 //    (1) Read memory array at Address ADreg
 //    (2) Updates DOreg with output from memory array
 //    (3) Check if the address AD is valid address

always @ (normal_mode or R_WBreg or WL_Enable or ADreg or dis_err_msgs or inputs_x_reg)
begin: read_data_block
  if(normal_mode && WL_Enable && R_WBreg == 1) begin
    if (is_AD_x(getAD(ADreg)) == 1) begin
    DOreg  <= {NB{1'bx}} ;
    end 
    else if (is_AD_within_range(getAD(ADreg)) == 0) begin
      if (!dis_err_msgs) begin
        $display("===ERROR=== (cftssc) : Read AD=%h Out Of Range in memory S8TSSC_01024x032_008_18 in instance %m at time=%t\n", ADreg, $time);
      end  
    end
    else if (inputs_x_reg === 1'b1) begin
      DOreg <= {NB{1'bx}} ;
    end 
    else begin
      DOreg <= memory[getAD(ADreg)];
	  end
  end
  else ;
end

task is_Floating_Signal;
input ENreg ;
input [(NB - 1) : 0] DIreg;
input [(NB - 1) : 0] BENreg;
input [(NA - 1) : 0] ADreg;
integer k;
integer flag;
begin
    flag = 0 ;
    if (ENreg === 1'bz || R_WBreg === 1'bz || vgnd === 1'bz) 
        flag = 1 ;  
    for (k = 0 ; k < NA ; k = k + 1) begin
        if (ADreg[k] === 1'bz) begin
            flag = 1 ;
            k = NA ;
        end
    end
    for (k = 0 ; k < NB ; k = k + 1) begin
        if (DIreg[k] === 1'bz || BENreg[k] === 1'bz) begin
            flag = 1 ;
            k = NB ;
        end
    end

  if (flag == 1)
    if (!dis_err_msgs) begin
      $display("===ERROR=== (cftssc) : Floating signal found in test mode: EN= %b R_WB=%b vgnd= %b AD= %b DI= %b BEN= %b in instance %m at time=%d", ENreg, R_WBreg, vgnd, ADreg, DIreg, BENreg, $time) ;
    end
    else begin
    end
    else begin
    end
  end
endtask

function is_AD_x;
  input [(NA - 1) : 0] ADreg;
  integer k;
  begin
    is_AD_x = 0;
    for (k = 0; k < NA; k = k + 1)
      if (ADreg[k] === 1'bx) begin
        is_AD_x = 1;
        k = NA ; 
      end
    end
endfunction

function is_AD_within_range;
  input [(NA - 1) : 0] ADreg;
  begin
    is_AD_within_range = ((ADreg >= 0) && (ADreg < NW)) ? 1 : 0 ;
  end
endfunction 

//========================================================================
// Following function gets the address bits from ADreg array.
// The mapping getAD <-- ADreg ommits the grounded bits.
//
function [(NA - 1) : 0] getAD;
  input [(12 - 1) : 0] ADreg;
  begin
                                            getAD[0] = ADreg[0] ;
                                                getAD[1] = ADreg[1] ;
                                                getAD[2] = ADreg[2] ;
                                                              getAD[3] = ADreg[11] ;
                                                  getAD[4] = ADreg[5] ;
                                                  getAD[5] = ADreg[6] ;
                                                  getAD[6] = ADreg[7] ;
                                                  getAD[7] = ADreg[8] ;
                                                  getAD[8] = ADreg[9] ;
                                                  getAD[9] = ADreg[10] ;
                                              end
endfunction

task write_x_in_whole_memory;
  integer k;
  begin
    for (k = 0; k < NW; k = k + 1)
      memory_mode_inst.memory[k] = 32'bx;
    end
endtask

endmodule

`endcelldefine

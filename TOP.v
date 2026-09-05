`timescale 1ns / 1ps

module TOP (
// Top-level Inputs and Outputs
	// Control
	input			reset,			// Remember: ACTIVE HIGH!!!
	input			clk,    		// 100 MHz

    // GPIO
	output [7:0] leds,

    //DDR2 Mem [copied from test]
   output 	hw_ram_rasn,
	output 	hw_ram_casn,
	output 	hw_ram_wen,
	output[2:0] hw_ram_ba,
	inout 	hw_ram_udqs_p,
	inout 	hw_ram_udqs_n,
	inout 	hw_ram_ldqs_p,
	inout 	hw_ram_ldqs_n,
	output 	hw_ram_udm,
	output 	hw_ram_ldm,
	output 	hw_ram_ck,
	output 	hw_ram_ckn,
	output 	hw_ram_cke,
	output 	hw_ram_odt,
	output[12:0] hw_ram_ad,
	inout [15:0] hw_ram_dq,
	inout 	hw_rzq_pin,
	inout 	hw_zio_pin,
   output 	status,
    
	// RS232 Pins
	input		rs232_rx,
	output	rs232_tx, 

    //Audio Pins
    input  [1:0] channel_sel,
    inout AUD_ADCLRCK,
    input AUD_ADCDAT,
    inout AUD_DACLRCK,
    output AUD_DACDAT,
    inout AUD_BCLK,
	 output AUD_I2C_SCLK, 
    inout  AUD_I2C_SDAT,
	 output AUD_XCK,
	 output AUD_MUTE
);

// Wires and Register Declarations
	// PicoBlaze Data Lines
	wire	[7:0]	port_id;
	wire	[7:0]	out_port;
	reg	[7:0]	in_port;
	wire	read_strobe;
	wire	write_strobe;
    reg   [7:0]   state_assignment;
    reg   [7:0]   slot_num;
	
   // PicoBlaze CPU Control Wires
	wire			pb_reset;
	wire			pb_interrupt;
	wire 			pb_clk;
	
	// UART wires
	wire		   write_to_uart;
	wire			uart_buffer_full;
	wire			uart_data_present;
	reg 			read_from_uart; // bc combinational assign
	wire			uart_reset;

	// UART Data Lines
	wire	[7:0]	uart_rx_data;
    // no tx wire bc fed directly by out_port

   //DDR2
    reg 		[25:0] start_address; //I added these
    reg 		[25:0] end_address;
    wire		[25:0] max_ram_address;

   reg 		[25:0] address;
   reg 		[15:0] RAMin; // changed to 16 bit for project
   wire		[15:0]	RAMout; //check these
	reg		[15:0]	dataOut; 
  	reg 		reqRead;
   reg 		enableWrite;
	reg 		ackRead = 0;
	reg [3:0]	mem_state=4'b0000;
	wire rdy, 	dataPresent;
	wire systemCLK;
	wire ram_reset;

   //LED memory test variables
   reg             memory_passed;
	
	//Audio wires
	wire [1:0] sample_end;
	wire [1:0] sample_req;
	wire [15:0] audio_output;
	wire [15:0] audio_input;
	wire main_clk;
	wire audio_clk;
   wire PLL_LOCKED;
	reg  done;
	reg  pause;
	
	parameter stInit = 4'b0000;
	parameter stReadFromCodec = 4'b0001;
	parameter stMemWrite = 4'b0010;
	parameter stMemReadReq  = 4'b0011;
	parameter stMemReadData = 4'b0100;
   parameter incAddressWrite = 4'b0101;
   parameter incAddressRead = 4'b0110;
   parameter stIdle = 4'b0111;
   parameter stWait = 4'b1000;
	parameter stWaitForCodec = 4'b1001;
	parameter stWaitSampleEndLow = 4'b1010;
	parameter stWaitSampleReqLow = 4'b1011;
	parameter stWaitForUnPause = 4'b1100;
	
    //Combinational control
	 assign status = rdy; // ready signal from ram [needed?]
	 assign audio_output = dataOut;
	 //assign audio_output = audio_input;
	 assign leds[1] = PLL_LOCKED;
	 assign leds[7:2] = 6'b000000;
	 assign AUD_XCK = audio_clk;
	 assign AUD_MUTE = 1'b1;
    //assign leds = memory_passed ? 8'b11111111 : 8'b00000000;
    //assign leds = dataOut; // output data read to leds [needed>> change for sure]
	
// 100 MHz clk for PB and UART
  clk_100 clk_for_pb
   (// Clock in ports
    .CLK_IN1(systemCLK),      // IN
    // Clock out ports
    .CLK_OUT1(pb_clk));    // OUT	
	 
// 50 Mhz and 11.2896 Mhz clk for Audio
	clk_wiz_v3_6 pll (
		.CLK_IN1 (pb_clk), // bc 100 Mhz
		.CLK_OUT1 (main_clk),   // 50 MHz
		.CLK_OUT2 (audio_clk),  // 11.2896 MHz
		.RESET (reset),
		.LOCKED (PLL_LOCKED)
	);

// I2C Protocol - FPGA is Master, Codec is Slave
	i2c_av_config av_config (
		.clk (pb_clk),
		.reset (reset | ~PLL_LOCKED),
		.i2c_sclk (AUD_I2C_SCLK),
		.i2c_sdat (AUD_I2C_SDAT),
		.status (leds[0])
	);
	
	//Audio Codec Instantiation
	audio_codec ac (
    .clk (audio_clk),
    .reset (reset),
    .sample_end (sample_end),
    .sample_req (sample_req),
    .audio_output (audio_output),
    .audio_input (audio_input),
    .channel_sel (2'b10),

    .AUD_ADCLRCK (AUD_ADCLRCK),
    .AUD_ADCDAT (AUD_ADCDAT),
    .AUD_DACLRCK (AUD_DACLRCK),
    .AUD_DACDAT (AUD_DACDAT),
    .AUD_BCLK (AUD_BCLK)
);

// PB CPU instantiation
    assign pb_reset = reset;
	
    picoblaze CPU (
		.port_id(port_id),
		.read_strobe(read_strobe),
		.in_port(in_port),
		.write_strobe(write_strobe),
		.out_port(out_port),
		.interrupt(pb_interrupt),
		.interrupt_ack(),
		.reset(pb_reset),
		.clk(pb_clk)
	);	

// UART instantiation
    assign uart_reset = reset; 

	rs232_uart UART (
		.tx_data_in(out_port), // UART accepts data from PB out_port
		.write_tx_data(write_to_uart), 
		.tx_buffer_full(uart_buffer_full),
		.rx_data_out(uart_rx_data),
		.read_rx_data_ack(read_from_uart),
		.rx_data_present(uart_data_present),
		.rs232_tx(rs232_tx),
		.rs232_rx(rs232_rx),
		.reset(uart_reset),
		.clk(pb_clk)
	);	

// RAM interface instantiation [confused about this but I think this is correct]
    assign ram_reset = reset;

	ram_interface_wrapper #(
    .DATA_BYTE_WIDTH(2)) RAMRapper (
		.address(address),				// input 
        .data_in(RAMin), 				// input
        .write_enable(enableWrite), 	//	input
        .read_request(reqRead), 		//	input
        .read_ack(ackRead), 
        .data_out(RAMout), 				// output from ram to wire
        .reset(ram_reset), 
        .clk(systemCLK), 
        .hw_ram_rasn(hw_ram_rasn), 
        .hw_ram_casn(hw_ram_casn),
        .hw_ram_wen(hw_ram_wen), 
        .hw_ram_ba(hw_ram_ba), 
        .hw_ram_udqs_p(hw_ram_udqs_p), 
        .hw_ram_udqs_n(hw_ram_udqs_n), 
        .hw_ram_ldqs_p(hw_ram_ldqs_p), 
        .hw_ram_ldqs_n(hw_ram_ldqs_n), 
        .hw_ram_udm(hw_ram_udm), 
        .hw_ram_ldm(hw_ram_ldm), 
        .hw_ram_ck(hw_ram_ck), 
        .hw_ram_ckn(hw_ram_ckn), 
        .hw_ram_cke(hw_ram_cke), 
        .hw_ram_odt(hw_ram_odt),
        .hw_ram_ad(hw_ram_ad), 
        .hw_ram_dq(hw_ram_dq), 
        .hw_rzq_pin(hw_rzq_pin), 
        .hw_zio_pin(hw_zio_pin), 
        .clkout(systemCLK), 
        .sys_clk(clk), 
        .rdy(rdy), 
        .rd_data_pres(dataPresent),
        .max_ram_address(max_ram_address) //end address will be final address
    );		


// PicoBlaze Control Logic
    always @(posedge pb_clk or posedge reset) begin // anvyl button press = negedge
        //resets value of strobe to uart

        if (reset) begin
            state_assignment <= 8'h00;
            slot_num <= 8'b00000000;
				pause <= 1'b0;
				in_port <= 8'h00;
				//write_to_uart <= 1'b0;
				read_from_uart <= 1'b0;
        end
		  
		  // if data on write_strobe port
		else begin
			//read_from_uart <= 1'b0;
			if (write_strobe) begin 
				case (port_id) // port_id determines what data is sent
					8'h00: state_assignment <= out_port;
					8'h01: slot_num <= out_port; 
					8'h07: pause <= out_port;
					//8'h03: write_to_uart <= 1'b1;
					default: ; // does nothing if other ports are written to
				endcase
			end

			case (port_id)
        	    8'h02: in_port <= uart_rx_data;
        	    8'h04: in_port <= {7'b0000000, uart_data_present}; //concatenation bc 1 bit
				 8'h05: in_port <= {7'b0000000, uart_buffer_full};
             8'h06: in_port <= {7'b0000000, done}; 
             default: in_port <= 8'h00; // returns done = 0 by default
        	endcase

			read_from_uart <= read_strobe & (port_id == 8'h02);

		end
	end
	 
	assign write_to_uart = write_strobe & (port_id == 8'h03);
	//assign read_from_uart = read_strobe & (port_id == 8'h02); // 4

//Mem and Codec Logic
   always @(posedge systemCLK or posedge reset) begin // systemCLK from ramWrapper

        if (reset) begin
            address <= 0; //check
            mem_state <= stInit;
            //memory_passed <= 1'b0;
            done <= 1'b0;
        end

        else begin
		      case (slot_num)
			       8'h01: begin //doing 10 second recordings for now for testing
			       //44100 samples/sec * 10 sec = 441000 samples (already accounted for * 2 bytes) = 441000 mem slots
			       //calc end by doing [(441000*slot_num)-1]

					     start_address <= 26'd0;
				        end_address <= 26'd440999;
					 end 
					 8'h02: begin
						  start_address <= 26'd441000;
						  end_address <= 26'd881999;
					 end 
					 8'h03: begin
						  start_address <= 26'd882000;
						  end_address <= 26'd1322999;
					 end 
					 8'h04: begin
						  start_address <= 26'd1323000;
						  end_address <= 26'd1763999;
					 end 
					 8'h05: begin
						  start_address <= 26'd1764000;
						  end_address <= 26'd2204999;
					 end
					 default: ;//protected by PSM logic, just here for HW rules
				endcase
            if (rdy) begin
                case (mem_state)
                    stInit: begin
                        ackRead <= 1'b0;
                        enableWrite <= 1'b0;
                        reqRead <= 1'b0;
                        mem_state <= stIdle;
                    end

                    stIdle: begin //need to wait for pb to change state assignment since pb is much slower
                        enableWrite <= 1'b0;
                        reqRead <= 1'b0;
                        ackRead <= 1'b0;
                        //memory_passed <= 1'b1;
                        done <= 1'b0;

                        if (state_assignment == 8'h02) begin
                            address <= start_address;
                            mem_state <= stReadFromCodec;
                        end
                        else if (state_assignment == 8'h01) begin
                            address <= start_address;
                            mem_state <= stMemReadReq;
                        end
                        else begin
                            mem_state <= stIdle;
                        end
                    end

                    stWait: begin
                        done <= 1'b1;
                        if (state_assignment == 8'h00) begin
                            mem_state <= stIdle;
                        end
                        else begin
                            mem_state <= stWait;
                        end
                    end

                    stReadFromCodec: begin
                        if (sample_end[1]) begin
                            RAMin <= audio_input;
                            mem_state <= stMemWrite;
                        end

                        else begin
                            mem_state <= stReadFromCodec;
                        end
                    end

                    stMemWrite: begin
                        enableWrite <= 1'b1;
                        mem_state <= incAddressWrite; 
                    end

                    incAddressWrite: begin
                        enableWrite <= 1'b0;
                        address <= address + 1'b1;
                        if (address == end_address) begin
                            mem_state <= stWait;
                        end
                        else begin
                            mem_state <= stWaitSampleEndLow;
                        end
                    end

                    stMemReadReq: begin
                        reqRead <= 1'b1;
                        mem_state <= stMemReadData;
                    end

                    stMemReadData: begin
                        reqRead <= 1'b0;
                        if(dataPresent) begin
                            dataOut <= RAMout;
                            ackRead <= 1'b1;
                            mem_state <= stWaitForCodec;
                        end
                        else begin
                            mem_state <= stMemReadData;
                        end
                    end
						  
						  stWaitForCodec: begin
						      ackRead <= 1'b0;
								if (sample_req[1]) begin
									mem_state <= incAddressRead;
								end
								else begin
									mem_state <= stWaitForCodec;
								end
						  end

                    incAddressRead: begin
                        reqRead <= 1'b0;
                        ackRead <= 1'b0;
                        address <= address + 1'b1;
                        if (address == end_address) begin
                            mem_state <= stWait;
                        end 
								else if (pause) begin
									mem_state <= stWaitForUnPause;
								end
                        else begin
                            mem_state <= stWaitSampleReqLow;
                        end
                    end
						  
						  stWaitForUnPause: begin
							   if (pause) begin
									mem_state <= stWaitForUnPause;
								end
								else begin
									mem_state <= stWaitSampleReqLow;
								end
						  end
						  
						  stWaitSampleEndLow: begin
						      if (!sample_end[1]) begin
                            mem_state <= stReadFromCodec;
                        end
						  end
						  
						  stWaitSampleReqLow: begin
						      if (!sample_req[1]) begin
                            mem_state <= stMemReadReq;
                        end
						  end
						  
                endcase
            end
        end
    end
endmodule
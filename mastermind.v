 module mastermind(
		CLOCK_50,						//	On Board 50 MHz
		// Your inputs and outputs here
        SW,
		// The ports below are for the VGA output.  Do not change.
		VGA_CLK,   						//	VGA Clock
		VGA_HS,							//	VGA H_SYNC
		VGA_VS,							//	VGA V_SYNC
		VGA_BLANK_N,						//	VGA BLANK
		VGA_SYNC_N,						//	VGA SYNC
		VGA_R,   						//	VGA Red[9:0]
		VGA_G,	 						//	VGA Green[9:0]
		VGA_B,   						//	VGA Blue[9:0]
		LEDR,
		LEDG,
		HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
		KEY
	);

	input	CLOCK_50;				//	50 MHz
	input [17:0] SW;
	input [3:0] KEY;
	// Declare your inputs and outputs here
	// Do not change the following outputs
	output VGA_CLK;      //	VGA Clock
	output VGA_HS;			//	VGA H_SYNC
	output VGA_VS;			//	VGA V_SYNC
	output VGA_BLANK_N;	//	VGA BLANK
	output VGA_SYNC_N;	//	VGA SYNC
	output [9:0] VGA_R;  //	VGA Red[9:0]
	output [9:0] VGA_G;	//	VGA Green[9:0]
	output [9:0] VGA_B;  //	VGA Blue[9:0]
	
	output [17:0] LEDR; // To flash when the player loses
	output [7:0] LEDG; // To flash when the player wins
	
	wire resetn, enter, load; // For getting user input
	
	assign resetn = SW[17]; 
	assign enter = !KEY[0]; // To enter the colours for the code/guess


	// Create the colour, x, y and writeEn wires that are inputs to the controller.
	wire [7:0] x;
	wire [6:0] y;
	wire [2:0] colour_in;
	wire writeEn;
	wire startCount;
   wire [7:0] x_out;
	wire [6:0] y_out;
	wire [2:0] colour_out;

	assign colour_in = SW[2:0];
	wire draw_En = 1'b1;


	// Create an Instance of a VGA controller - there can be only one!
	// Define the number of colours as well as the initial background
	// image file (.MIF) for the controller.
	vga_adapter VGA(
			.resetn(resetn),
			.clock(CLOCK_50),
			.colour(colour_out),
			.x(x_out),
			.y(y_out),
			.plot(writeEn),
			/* Signals for the DAC to drive the monitor. */
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK(VGA_BLANK_N),
			.VGA_SYNC(VGA_SYNC_N),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = "160x120";
		defparam VGA.MONOCHROME = "FALSE";
		defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
		defparam VGA.BACKGROUND_IMAGE = "MM_Final2.mif";

	datapath d0(
    	.enable(startCount),
		.clk(CLOCK_50),
		.fourbit(fourbyfour),
        .resetn(resetn),
       .x_out(x_out),
       .y_out(y_out),
       .x_in(x),
       .y_in(y)
	 );

	control c0(
	 .clk(CLOCK_50),
	 .resetn(resetn),
	 .go(draw_En),
	 .plot(writeEn),
	 .enable_counter(startCount)
	 );

	gameboard g0(
	   .clk(CLOCK_50),
	   .resetn(resetn),
	   .enter(enter),
		.colour_in(colour_in),
		.colour_out(colour_out),
		.current_state(curr_state),
		.x(x),
		.y(y),
		.leds(LEDR[17:0]),
		.ledg(LEDG[7:0])
	);
endmodule

module gameboard(
    clk,
    resetn,
    enter,
    colour_in,
	 colour_out,
	x,
	y,
	leds,
	ledg
);
	input clk, resetn, enter; 
	input [2:0] colour_in; // Colour entered by user
	reg codetoguess;  
	
	// To store the code and guesses entered by the players
	reg [2:0] code0, code1, code2, code3, guess0, guess1, guess2, guess3;
	reg [2:0] c;
	
	// Used when calculating wspot
	reg [2:0] code0_seen, code1_seen, code2_seen, code3_seen;
	reg [2:0] code0_rspot, code1_rspot,code2_rspot,code3_rspot;
	
	reg [2:0] rspot; // The number of spots the player got correct (both colour and position) in the current guess
	reg [2:0] wspot; // The number of colours the player got correct but in the wrong spot in the current guess
	
	// Used to make the LEDRs/LEDGs flash when player wins or loses
	reg [26:0] count;
	output reg [17:0] leds; // To flash when the player loses
	output reg [7:0] ledg; // To flash when the player wins
	
	// The positions for drawing the boxes (for the codes/guesses/clues)
	output reg [7:0] x; 
	output reg [6:0] y;
	
	// To get the colour of the boxes to display on the board
	output reg [2:0] colour_out;
	reg [5:0] current_state;
	reg [5:0] next_state;

// States and their binary representations
localparam SETUP              = 5'b11111,
           CODE_0             = 5'b11101,
           CODE_1_WAIT        = 5'b11100,
           CODE_1             = 5'b10100,
           CODE_2_WAIT        = 5'b10101,
           CODE_2             = 5'b10111,
           CODE_3_WAIT        = 5'b10110,
           CODE_3             = 5'b10010,
           GUESS_0_WAIT       = 5'b10000,
           GUESS_0            = 5'b00000,
           GUESS_1_WAIT       = 5'b00001,
           GUESS_1            = 5'b00011,
           GUESS_2_WAIT       = 5'b00010,
           GUESS_2            = 5'b00110,
           GUESS_3_WAIT       = 5'b00111,
           GUESS_3            = 5'b00101,
           ASSESS_GUESS_WAIT  = 5'b00100,
           ASSESS_GUESS       = 5'b01100,
	   CLUE_0_WAIT        = 5'b01101,
           CLUE_0             = 5'b01001,
	   CLUE_1_WAIT        = 5'b01011,
	   CLUE_1             = 5'b01010,
	   CLUE_2_WAIT        = 5'b11010,
	   CLUE_2	      = 5'b11011,
	   CLUE_3_WAIT	      = 5'b11001,
     	   CLUE_3             = 5'b11000,
           ROW_BACK           = 5'b01000,
           GAME_OVER          = 5'b01110,
           WON                = 5'b11110,
           LOST               = 5'b01111;

// Finite state machine that drives the game
 always @(*)
    begin: state_table
            case (current_state)
                SETUP: next_state = resetn ? CODE_0 : SETUP;
                CODE_0: next_state = enter ? CODE_1_WAIT : CODE_0; // Loop in current state until value is input
                CODE_1_WAIT: next_state = enter ? CODE_1_WAIT : CODE_1; // Loop in current state until go signal goes low
                CODE_1: next_state = enter ? CODE_2_WAIT : CODE_1;
                CODE_2_WAIT: next_state = enter ? CODE_2_WAIT : CODE_2;
                CODE_2: next_state = enter ? CODE_3_WAIT : CODE_2;
                CODE_3_WAIT: next_state = enter ? CODE_3_WAIT : CODE_3;
                CODE_3: next_state = enter ? GUESS_0_WAIT : CODE_3;
                GUESS_0_WAIT: next_state = enter ? GUESS_0_WAIT : GUESS_0;
                GUESS_0: next_state = enter ? GUESS_1_WAIT : GUESS_0;
                GUESS_1_WAIT: next_state = enter ? GUESS_1_WAIT : GUESS_1;
                GUESS_1: next_state = enter ? GUESS_2_WAIT : GUESS_1;
                GUESS_2_WAIT: next_state = enter ? GUESS_2_WAIT : GUESS_2;
                GUESS_2: next_state = enter ? GUESS_3_WAIT : GUESS_2;
                GUESS_3_WAIT: next_state = enter ? GUESS_3_WAIT : GUESS_3;
                GUESS_3: next_state = enter ? ASSESS_GUESS_WAIT : GUESS_3;
                ASSESS_GUESS_WAIT: next_state = enter ? ASSESS_GUESS_WAIT : ASSESS_GUESS;
	        ASSESS_GUESS: next_state = ((y == 7'b0011100) || (rspot == 3'b100)) ? GAME_OVER : CLUE_0_WAIT; // Go to gameover state if player won or finished entering 10 rows of guesses. Else go to clue_0_wait
		CLUE_0_WAIT: next_state = enter ? CLUE_0_WAIT : CLUE_0;
		CLUE_0: next_state = enter ? CLUE_1_WAIT : CLUE_0;
		CLUE_1_WAIT: next_state = enter ? CLUE_1_WAIT : CLUE_1;
		CLUE_1: next_state = enter ? CLUE_2_WAIT : CLUE_1;
		CLUE_2_WAIT: next_state = enter ? CLUE_2_WAIT : CLUE_2;
		CLUE_2: next_state = enter ? CLUE_3_WAIT : CLUE_2;
		CLUE_3_WAIT: next_state = enter ? CLUE_3_WAIT : CLUE_3;
		CLUE_3: next_state = enter ? ROW_BACK : CLUE_3;
                ROW_BACK: next_state = enter ? GUESS_0_WAIT : ROW_BACK;
		    GAME_OVER: next_state = (rspot == 3'b100) ? WON : LOST; // If player guesses the code correctly, go to win state, else go to lose state
                WON: next_state = enter ? SETUP : WON;
                LOST: next_state = enter ? SETUP : LOST;
            default: next_state = SETUP;
        endcase
    end

    // Output logic aka all of our datapath control signals
    always @(*)
    begin: enable_signals
        case (current_state)
			SETUP: begin
				// By default make all our signals and wires 0
				rspot = 3'b000;
				wspot = 3'b000;
				x = 8'b00111111;
				code0 = 3'b000;
				code1 = 3'b000;
				code2 = 3'b000;
				code3 = 3'b000;
				guess0 = 3'b000;
				guess1 = 3'b000;
				guess2 = 3'b000;
				guess3 = 3'b000;
				code0_seen = 3'b000;
				code1_seen = 3'b000;
				code2_seen = 3'b000;
				code3_seen = 3'b000;
				codetoguess = 1'b1;
			end
			// In each code state, set the colour and x positions for drawing the box that corresponds to each code
			CODE_0: begin
				colour_out <= colour_in;
				code0 <= colour_in;
				x <= 8'b01000010;
			end
			// In each code_i_wait state, reset the colour of the code_i box to black to prevent the guesser from seeing the actual code
			CODE_1_WAIT: begin
				colour_out = 3'b000;
			end
			CODE_1: begin
				colour_out <= colour_in;
				code1 <= colour_in;
				x <= 8'b01001010;
			end
			CODE_2_WAIT: begin
				colour_out = 3'b000;
			end
			CODE_2: begin
				colour_out <= colour_in;
				code2 <= colour_in;
				x <= 8'b01010010;
			end
			CODE_3_WAIT: begin
				colour_out = 3'b000;
			end
			CODE_3: begin
				colour_out <= colour_in;
				c <= colour_in;
				code3 <= c;
				x <= 8'b01011010;
			end
			GUESS_0_WAIT: begin
				colour_out <= colour_in;
				x = 8'b00111111;
				end
			// Set the colour and x positions for each guess_i state
			GUESS_0: begin
				colour_out <= colour_in;
				guess0 <= colour_in;
				x <= 8'b00111111;
				// Resetting the values for codei_seen
				code0_seen = 3'b000;
				code1_seen = 3'b000;
				code2_seen = 3'b000;
				code3_seen = 3'b000;
				code0_rspot = 3'b000;
				code1_rspot = 3'b000;
				code2_rspot= 3'b000;
				code3_rspot = 3'b000;
				codetoguess = 3'b0;
				end
			GUESS_1: begin
				colour_out <= colour_in;
				guess1 <= colour_in;
				x <= 8'b01000111;
			end
			GUESS_2: begin
				colour_out <= colour_in;
				guess2 <= colour_in;
				x <= 8'b01001111;
			end
			GUESS_3: begin
				colour_out <= colour_in;
				guess3 <= colour_in;
				x <= 8'b01010111;
			end
			// Checks the user's guess against actual code and calculates rspot and wspot
			ASSESS_GUESS: begin
				// Binary addition needed
				rspot = (guess0 == code0) + (guess1 == code1) + (guess2 == code2) + (guess3 == code3);
				
				// Check whether the player got any of the guesses correct
				if (guess0 == code0)
					code0_rspot = 3'b001;
				
				if (guess1 == code1)
					code1_rspot = 3'b001;
				
				if (guess2 == code2)
					code2_rspot = 3'b001;
			
				if (guess3 == code3)
					code3_rspot = 3'b001;
				
				// Logic for calculating wspot (sets codei_seen to true whenever guessi matches codei, codei has not been seen yet
				// and codei_rspot is false (to makesure we don't count the guesses that the player got correct)
				if ((guess0 == code1) && (code1_seen == 3'b000) && (code0_rspot == 3'b000) && (code1_rspot == 3'b000))
					code1_seen = 3'b001;
				else if ((guess0 == code2) && (code2_seen == 3'b000) && (code0_rspot == 3'b000) && (code2_rspot == 3'b000))
					code2_seen = 3'b001;
				else if ((guess0 == code3) && (code3_seen == 3'b000) && (code0_rspot == 3'b000) && (code3_rspot == 3'b000))
					code3_seen = 3'b001;
			

				if ((guess1 == code0) && (code0_seen == 3'b000) && (code1_rspot == 3'b000) && (code0_rspot == 3'b000))
				  code0_seen = 3'b001;
				else if ((guess1 == code2) && (code2_seen == 3'b000) && (code1_rspot == 3'b000) && (code2_rspot == 3'b000))
				  code2_seen = 3'b001;
				else if ((guess1 == code3) && (code3_seen == 3'b000) && (code1_rspot == 3'b000) && (code3_rspot == 3'b000))
				  code3_seen = 3'b001;
			
			
				if ((guess2 == code0) && (code0_seen == 3'b000) && (code2_rspot == 3'b000) && (code0_rspot == 3'b000))
					code0_seen = 3'b001;
				else if ((guess2 == code1) && (code1_seen == 3'b000) && (code2_rspot == 3'b000) && (code1_rspot == 3'b000))
					code1_seen = 3'b001;
				else if ((guess2 == code3) && (code3_seen == 3'b000) && (code2_rspot == 3'b000) && (code3_rspot == 3'b000))
					code3_seen = 3'b001;
			
				if ((guess3 == code0) && (code0_seen == 3'b000) && (code3_rspot == 3'b000) && (code0_rspot == 3'b000))
					code0_seen = 3'b001;
				else if ((guess3 == code1) && (code1_seen == 3'b000) && (code3_rspot == 3'b000) && (code1_rspot == 3'b000))
					code1_seen = 3'b001;
				else if ((guess3 == code2) && (code2_seen == 3'b000) && (code3_rspot == 3'b000) && (code2_rspot == 3'b000))
					code2_seen = 3'b001;

		
				// Calculate wspot
				wspot <= code0_seen + code1_seen + code2_seen + code3_seen;
			end
		        // In each clue_i state we set the colour of the clue_i box to red, white or black depending on the rspot and wspot values 
			CLUE_0: begin
				x = 8'b01100001;
				if (rspot >= 3'b001)
					colour_out = 3'b100;
				else if (wspot >= 3'b001)
					colour_out = 3'b111;
				else
					colour_out = 3'b000;
			end
			CLUE_1_WAIT: begin
				colour_out <= 3'b000;
				x = 8'b01100110;
			end
			CLUE_1: begin
				x = 8'b01100110;
				if ((rspot >= 3'b010))
					colour_out = 3'b100;
				else if ((wspot >= 3'b001 && rspot == 3'b001) || (wspot >= 3'b010 && rspot == 3'b000))
					colour_out = 3'b111;
				else
					colour_out = 3'b000;
			end
			CLUE_2_WAIT: begin
				colour_out <= 3'b000;
				x = 8'b01101011;
			end
			CLUE_2: begin
				x = 8'b01101011;
				if ((rspot >= 3'b011))
					colour_out = 3'b100;
				else if ((wspot >= 3'b011 && rspot == 3'b000) || (wspot >= 3'b010 && rspot == 3'b001) || 
				(wspot >= 3'b001 && rspot == 3'b010))
					colour_out = 3'b111;
				else
					colour_out = 3'b000;
			end
			CLUE_3_WAIT: begin
				colour_out <= 3'b000;
				x = 8'b01110000;
			end
			CLUE_3: begin
				x = 8'b01110000;
				if ((rspot == 3'b100))
					colour_out = 3'b100;
				else if ((wspot == 3'b100 && rspot == 3'b000) || (wspot >= 3'b011 && rspot == 3'b001) || 
				(wspot >= 3'b010 && rspot == 3'b010) ||  (wspot >= 3'b001 && rspot == 3'b011))
					colour_out = 3'b111;
				else
					colour_out = 3'b000;
			end
			// default:    // don't need default since we already made sure all of our outputs were assigned a value at the start of the always block
        endcase
    end
	// To increment count that is used for flashing the LEDRs/LEDGs when the player wins/loses
	always @(posedge clk)
	begin
		if (!resetn)
			count <= 0;
		else
			count <= count + 1;
	end
	
	// Flash the leds (RED) when player loses and ledgs (GREEN) when the player wins
	always @(*)
	begin
		case (current_state)
			LOST: begin
				 leds[17] <= count[23];
				 leds[16] <= count[24];
				 leds[15] <= count[23];
				 leds[14] <= count[24];
				 leds[13] <= count[23];
				 leds[12] <= count[24];
				 leds[11] <= count[23];
				 leds[10] <= count[24];
				 leds[9] <= count[23];
				 leds[8] <= count[24];
				 leds[7] <= count[23];
				 leds[6] <= count[24];
				 leds[5] <= count[23];
				 leds[4] <= count[24];
				 leds[3] <= count[23];
				 leds[2] <= count[24];
				 leds[1] <= count[23];
				 leds[0] <= count[24];
			end
			WON: begin
				 ledg[7] <= count[23];
				 ledg[6] <= count[24];
				 ledg[5] <= count[23];
			         ledg[4] <= count[24];
				 ledg[3] <= count[23];
				 ledg[2] <= count[24];
				 ledg[1] <= count[23];
				 ledg[0] <= count[24];
			end
		endcase
	end
	
	// Calculating current y position
	always @(*)
	begin
		if (current_state == SETUP)
			y_decrement = 7'b0000000;
		else if (current_state == ROW_BACK)
			y_decrement = y - 7'b0001001;
	end

	always@(posedge clk)
	begin
		// Reset y position in SETUP state
		if (current_state == SETUP)
			y = 7'b0010001;
		// Set y to the position of the first row of guesses
		else if (current_state == GUESS_0_WAIT && codetoguess == 1'b1)
			y <= 7'b1101101;
		// Decrement y in ROW_BACK state
		else if (current_state == ROW_BACK)
			y <= y_decrement;
	end

   // current_state registers
    always@(posedge clk)
    begin
        if(!resetn)
            current_state <= SETUP;
		else
            current_state <= next_state;
         // state_FFS
	end
endmodule

module control(
    input clk,
    input resetn,
    input go,
    output reg plot,
    output reg enable_counter
    );
	reg [3:0] current_state, next_state;

	localparam  S_INIT      = 2'b00,
                S_CYCLE_0       = 2'b01,
                S_CYCLE_1       = 2'b11,
		S_CYCLE_2  	= 2'b10;

	// Next state logic aka our state table
    always@(*)
    begin: state_table
            case (current_state)
                S_INIT: next_state = go ? S_CYCLE_0: S_INIT;// Loop in current state until value is input
                S_CYCLE_0: next_state = S_CYCLE_1;
                S_CYCLE_1: next_state = S_CYCLE_2;
				S_CYCLE_2: next_state = S_INIT;
            default: 	   next_state = S_INIT;
        endcase
    end // state_table
   
   // Output logic aka all of our datapath control signals
    always @(*)
    begin: enable_signals
        // By default make all our signals 0
		plot = 1'b0;
		enable_counter = 1'b0;
		case(current_state)
			S_INIT: begin
				plot = 1'b0;
				enable_counter = 1'b0;
			end
			S_CYCLE_0: begin
				plot = 1'b1;
				enable_counter = 1'b1;
			end
        // default:    // don't need default since we already made sure all of our outputs were assigned a value at the start of the always block
        endcase
    end // enable_signals

   // current_state registers
    always@(posedge clk)
    begin: state_FFs
        if(!resetn)
            current_state <= S_INIT;
        else
            current_state <= next_state;
    end // state_FFS

endmodule

module datapath(enable, clk, x_in, y_in, resetn, x_out, y_out, fourbit);
   input clk, enable, resetn;
   input [7:0] x_in;
   input [6:0] y_in;
   input fourbit;
   output [7:0] x_out;
   output [6:0] y_out;
   reg [3:0] counter;
   
   // The logic part was taken from Lab6Part2
   // Counter -> used for drawing the 4x4 boxes for the codes/guesses/clues
    always @(posedge clk)
    begin
        if (resetn == 1'b0)
            counter <= 4'b0000;
        else if(enable == 1'b1)
	    counter <= counter + 1'b1;
    end

   // Increment x and y by the counter to draw the square boxes for the codes/guesses/clues
   assign x_out = x_in + counter[1:0];
   assign y_out = y_in + counter[3:2];
endmodule

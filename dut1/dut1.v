`include "tap_top.v"
`include "counter.v"
`include "ip.v"

module dut1(tck,tdi,tdo,tms,trstn,
            rstn,
            done,
            test_bus,
            din, dout,
            p1, p2, p3, p4,
            vdd, ana
          );

  input tck, tdi, tms, trstn;
  input rstn;
  input [31:0] din;
  input p1;
  input p2;
  input [3:0] p3;
  input [3:0] p4;
  inout vdd;

  output tdo;
  output done;
  output [15:0] test_bus;
  output [31:0] dout;
  output ana;

  wire [31:0] count;
  wire shift_dr;
  wire debugger_en;
  wire ip1_en;
  wire ip2_en;
  wire tdi_o;
  wire debug_tdo_i;
  wire ip1_tdo_i;
  wire ip2_tdo_i;
  wire capture_dr;
  wire update_dr;
  wire [31:0] address;
  wire [31:0] data;
  wire rw_en;
  wire read_en;
  wire count_clk;
  wire count_en;
  wire count_reset;

  // Used to test poking and peeking a real value
  real real_val;

  // Used to test poking and peeking a memory
  reg[31:0] ram[0:127];  // 128 32-bit words

  // Used for testing peek and poke methods
  reg [15:0] test_data;
  assign test_bus = test_data;

  tap_top tap (
    .tms_pad_i(tms),
    .tck_pad_i(tck),
    .tdi_pad_i(tdi),
    .tdo_pad_o(tdo),
    .trstn_pad_i(trstn & rstn),
    .shift_dr_o(shift_dr),
    .debug_select_o(debugger_en),
    .ip1_select_o(ip1_en),
    .ip2_select_o(ip2_en),
    .tdi_o(tdi_o),
    .debug_tdo_i(debug_tdo_i),
    .ip1_tdo_i(ip1_tdo_i),
    .ip2_tdo_i(ip2_tdo_i),
    .update_dr_o(update_dr),
    .capture_dr_o(capture_dr)
  );

  counter counter (
    .clock(count_clk),
    .reset(count_reset),
    .count(count)
  );

  wire ip1_shift;
  wire ip1_update;
  wire ip1_capture;
  assign ip1_shift = shift_dr && ip1_en;
  assign ip1_update = update_dr && ip1_en;
  assign ip1_capture = capture_dr && ip1_en;

  ip ip1 (
    .tdi(tdi_o),
    .shift(ip1_shift),
    .update(ip1_update),
    .capture(ip1_capture),
    .tck(tck),
    .reset_n(rstn),
    .tdo(ip1_tdo_i)
  );

  wire ip2_shift;
  wire ip2_update;
  wire ip2_capture;
  assign ip2_shift = shift_dr && ip2_en;
  assign ip2_update = update_dr && ip2_en;
  assign ip2_capture = capture_dr && ip2_en;

  ip ip2 (
    .tdi(tdi_o),
    .shift(ip2_shift),
    .update(ip2_update),
    .capture(ip2_capture),
    .tck(tck),
    .reset_n(rstn),
    .tdo(ip2_tdo_i)
  );

  //****************************************************************
  // DEBUGGER INTERFACE
  //****************************************************************
  reg [65:0] dr;

  // DR shift register
  always @ (posedge tck or negedge rstn) begin
    if (rstn == 0)
      dr[65:0] <= 66'b0;
    else if (shift_dr == 1 && debugger_en == 1)
      begin
        dr[65] <= tdi_o;
        dr[64:0] <= dr[65:1];
      end
    else
      dr[65:0] <= dr[65:0];
  end

  assign rw_en = dr[65];
  assign read_en = dr[64];
  assign address[31:0] = dr[63:32];
  assign data[31:0] = dr[31:0];
  assign debug_tdo_i = dr[0];
  assign write_register = update_dr && debugger_en && !read_en && rw_en;
  assign read_register = capture_dr && debugger_en && read_en && rw_en;

  // Done pin
  reg done_bit;
  assign done = done_bit;

  always @ (negedge rstn) begin
    done_bit <= 1;
  end

  //****************************************************************
  // DEVICE RAM
  //****************************************************************

  always @ (negedge tck or negedge rstn) begin
    if (write_register && address[31] == 1'b1)
      ram[address[30:0]] <= data;
    else if (read_register && address[31] == 1'b1)
      dr[31:0] <= ram[address[30:0]];
  end


  //****************************************************************
  // DEVICE REGISTERS
  //****************************************************************

  reg [31:0] ctrl;  // Address 0
  reg [31:0] cmd;  // Address 4
  reg [31:0] data_out;  // Address 0xC

  always @ (negedge tck or negedge rstn) begin
    if (rstn == 0)
      ctrl[31:0] <= 32'b0;
    else if (write_register && address == 32'b0)
      ctrl[31:0] <= data;
    else
      ctrl[31:0] <= ctrl[31:0];
  end

  assign count_en = ctrl[0];
  assign count_reset = ctrl[1];
  assign count_clk = tck && count_en;

  // CMD register

  always @ (negedge tck or negedge rstn) begin
    if (rstn == 0)
      cmd[31:0] <= 32'b0;
    else if (write_register && address == 32'h4)
      cmd[31:0] <= data;
  end

  // Some nonsense to create some pin pseudo random output for us to capture
  // based on the value on din whenever a certain command code is written
  reg [31:0] i;
  always @ (negedge tck) begin
    if (cmd == 32'h55)
      begin
        cmd[31] <= 32'h8000_0055;
        i <= 0;
      end
  end
  always @ (negedge tck) begin
    if (cmd == 32'h8000_0055)
      begin
        if (i == 50)
          cmd[31:0] <= 0;
        else
          begin
            if (i == 0)
              data_out[31:0] <= din[31:0];
            else if (i == 50)
              cmd[31:0] <= 0;
            else
              data_out[31:0] <= ({data_out[30:0], 1'b0} ^ data_out[31:0]);
            i <= i + 1;
          end
      end
  end

  // Emulate a command running by taking the done pin low for a while and then
  // put it high, this is used for testing match loops
  always @ (negedge tck) begin
    if (cmd == 32'h75)
      begin
        cmd[31] <= 32'h8000_0075;
        i <= 1000;
        done_bit <= 0;
      end
  end
  always @ (negedge tck) begin
    if (cmd == 32'h8000_0075)
      begin
        if (i > 0)
          i <= i - 1;
        else
          done_bit <= 1;
      end
  end

  // Data out register

  always @ (negedge tck or negedge rstn) begin
    if (rstn == 0)
      data_out[31:0] <= 32'b0;
    else if (write_register && address == 32'hC)
      data_out[31:0] <= data;
  end

  assign dout = data_out;

  // Analog test register

  reg osc_out;
  reg bgap_out;
  reg vdd_div4;
  wire vdd_valid;

  `ifdef ORIGEN_WREAL
  wreal vdd;
  wreal ana;
  real osc;

  assign vdd_valid = (vdd >= 1.1) ? 1 : 0;

  reg [7:0] sine1,cos1;
  reg [7:0] sine2, cos2;
  always @ (posedge tck or negedge rstn) begin
    if (rstn == 0 || vdd_valid != 1) begin
      sine2 <= 0;
      cos2 <= 120;
    end else begin
      sine2 <= sine1;
      cos2 <= cos1;
    end
  end

  always @* begin
    sine1 = sine2 + {cos2[7], cos2[7], cos2[7], cos2[7:3]};
    cos1  = cos2 - {sine1[7], sine1[7], sine1[7], sine1[7:3]};
    osc = (sine1[7] == 0 ? sine1[6:0] + 120 : sine1[6:0]) / 200.0;
  end

  assign ana = ana_mux(vdd, osc, bgap_out, osc_out, vdd_div4);

  function real ana_mux(input real vdd, input real osc, input reg bgap_out, input reg osc_out, input reg vdd_div4);
    if (vdd_div4 == 1'b1)
      ana_mux = vdd / 4;
    else if (bgap_out == 1'b1)
      ana_mux = 1.25;
    else if (osc_out == 1'b1)
      ana_mux = osc;
    else
      ana_mux = `wrealZState;
  endfunction

  `else
  wire vdd;
  wire ana;
  assign vdd_valid = vdd;
  assign ana = vdd;
  `endif

  always @ (negedge tck or negedge rstn) begin
    if (rstn == 0) begin
      osc_out  <= 1'b0;
      bgap_out <= 1'b0;
      vdd_div4 <= 1'b0;
    end else if (write_register && address == 32'h1C) begin
      bgap_out <= data[1];
      osc_out  <= data[2];
      vdd_div4 <= data[3];
    end
  end

  // Read regs
  always @ (negedge tck) begin
    if (read_register && address == 32'b0)
      dr[31:0] <= ctrl[31:0];
    else if (read_register && address == 32'h4)
      dr[31:0] <= cmd[31:0];
    else if (read_register && address == 32'h8)
      dr[31:0] <= count[31:0];
    else if (read_register && address == 32'hC)
      dr[31:0] <= data_out[31:0];
    else if (read_register && address == 32'h10)
      dr[31:0] <= din[31:0];
    else if (read_register && address == 32'h14)
      dr[31:0] <= {24'b0, p4[3:0], p3[3:0], p2, p1};
    else if (read_register && address == 32'h1C)
      dr[31:0] <= {29'b0, osc_out, bgap_out, vdd_valid};
  end

endmodule

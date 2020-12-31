module dut1(tck,tdi,tdo,tms,trstn,
            rstn,
            done,
            test_bus,
            din, dout,
            p1, p2, p3, p4,
            vdd, ana, osc
          );

  input tck, tdi, tms, trstn;
  input rstn;
  input [31:0] din;
  input p1;
  input p2;
  input [3:0] p3;
  input [3:0] p4;
  input osc;
  inout vdd;

  output tdo;
  output done;
  output [15:0] test_bus;
  output [31:0] dout;
  output ana;

`ifdef ORIGEN_WREAL
  wreal vdd;
  wreal ana;
`endif
endmodule

`timescale 1ns/1ps
module tb_bf16_codec;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,wv=0,pr=0,rv=0,rr=0;
    wire wr,pv,rready,ov,error;
    reg [511:0] wd;reg [7:0] wb,rb;
    wire [639:0] pd;wire [6:0] pb;wire [7:0] pbase;
    reg [639:0] rd;reg [6:0] rbytes;
    wire [511:0] od;
    bf16_codec_pair dut(clk,rst,wv,wr,wd,wb,pv,pr,pd,pb,pbase,rv,rready,rd,rbytes,rb,ov,rr,od,error);
    integer f,rc,cases,hold,i,expected_bytes;
    reg [511:0] original;
    reg [639:0] expected;
    reg [7:0] base;
    reg [639:0] saved;
    reg [511:0] burst_original[0:15];
    reg [639:0] burst_encoded[0:15];
    reg [7:0] burst_base[0:15];
    integer burst_bytes[0:15];
    initial begin
        cases=0;wd=0;wb=0;rd=0;rb=0;rbytes=0;
        repeat(3) @(negedge clk);rst=0;
        f=$fopen("vectors.txt","r");if(!f)$fatal(1,"Missing vectors");
        // Compare the packed frame as well as the restored input bits.
        while(!$feof(f))begin
            rc=$fscanf(f,"%h %h %h %d\n",base,original,expected,expected_bytes);
            if(rc==4)begin
                if(cases<16)begin burst_original[cases]=original;burst_encoded[cases]=expected;burst_base[cases]=base;burst_bytes[cases]=expected_bytes;end
                @(negedge clk);wd=original;wb=base;wv=1;pr=0;
                @(posedge clk);if(!wr)$fatal(1,"Unexpected encoder stall");
                @(negedge clk);wv=0;
                if(!pv || pd!==expected || pb!==expected_bytes || pbase!==base)$fatal(1,"Encoder mismatch case %0d",cases);
                saved=pd;
                // Stall for different durations and require the output to remain stable.
                hold=cases%3;
                repeat(hold)begin @(negedge clk);if(!pv || pd!==saved)$fatal(1,"Encoder hold failure");end
                pr=1;
                @(negedge clk);pr=0;rd=saved;rb=base;rbytes=expected_bytes;rv=1;rr=0;
                @(posedge clk);if(!rready)$fatal(1,"Unexpected decoder stall");
                @(negedge clk);rv=0;
                if(!ov || error || od!==original)$fatal(1,"Decoder mismatch case %0d",cases);
                repeat(hold)begin @(negedge clk);if(!ov || od!==original)$fatal(1,"Decoder hold failure");end
                rr=1;@(negedge clk);rr=0;cases=cases+1;
            end
        end
        $fclose(f);
        // Both elastic paths accept a fresh independent frame on each clock.
        @(negedge clk);pr=1;rr=1;
        for(i=0;i<16;i=i+1)begin
            wd=burst_original[i];wb=burst_base[i];wv=1;
            rd=burst_encoded[i];rbytes=burst_bytes[i];rb=burst_base[i];rv=1;
            @(posedge clk);if(!wr || !rready)$fatal(1,"Burst stalled");
            @(negedge clk);
            if(!pv || pd!==burst_encoded[i] || pb!==burst_bytes[i] || pbase!==burst_base[i])$fatal(1,"Burst encoder mismatch");
            if(!ov || error || od!==burst_original[i])$fatal(1,"Burst decoder mismatch");
        end
        wv=0;rv=0;@(negedge clk);
        // Base 242 is outside the permitted range and must set the error flag.
        rb=242;rd=burst_encoded[0];rbytes=burst_bytes[0];rv=1;
        @(negedge clk);rv=0;if(!ov || !error)$fatal(1,"Invalid base accepted");
        @(negedge clk);rb=burst_base[0];
        // A bad frame length must be reported, even if the data bits look valid.
        @(negedge clk);rv=1;rbytes=0;rr=1;
        @(negedge clk);rv=0;if(!ov || !error)$fatal(1,"Malformed length accepted");
        // Reset aborts pending frames in both paths.
        @(negedge clk);wv=1;rv=1;rr=0;pr=0;
        @(negedge clk);wv=0;rv=0;rst=1;
        @(negedge clk);rst=0;if(pv || ov)$fatal(1,"Reset did not abort");
        $display("PASS cases=%0d exact_encoder=1 exact_decoder=1 backpressure=1 reset_abort=1 bad_length=1 bad_base=1 burst_frames=16",cases);
        $finish;
    end
    initial begin #30000000;$fatal(1,"Watchdog");end
endmodule

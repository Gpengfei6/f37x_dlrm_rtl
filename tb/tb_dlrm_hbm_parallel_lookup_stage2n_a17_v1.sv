`timescale 1ns/1ps
// Independent public-port scoreboard. No hierarchical DUT references.
module tb_dlrm_hbm_parallel_lookup_stage2n_a17_v1;
  logic clk=0, rst=1;
  always #5 clk=~clk;
  logic load_valid=0, load_ready, busy, all_loaded, done;
  logic [3:0][63:0] table_base_addr='0;
  logic [3:0][31:0] lookup_index='0;
  logic error_valid, error_ready=0;
  logic [3:0] error_mask, committed_mask;
  logic cfg_valid, cfg_ready=0;
  logic [1:0] cfg_index;
  logic [127:0] cfg_data;
  logic [3:0][0:0] m_axi_arid, m_axi_rid='0;
  logic [3:0][63:0] m_axi_araddr;
  logic [3:0][7:0] m_axi_arlen;
  logic [3:0][2:0] m_axi_arsize, m_axi_arprot;
  logic [3:0][1:0] m_axi_arburst, m_axi_rresp='0;
  logic [3:0] m_axi_arlock, m_axi_arvalid, m_axi_arready='0;
  logic [3:0][3:0] m_axi_arcache, m_axi_arqos;
  logic [3:0][127:0] m_axi_rdata='0;
  logic [3:0] m_axi_rlast='1, m_axi_rvalid='0, m_axi_rready;
  dlrm_hbm_parallel_lookup_stage2n_a17_v1 dut (.*);

  logic [3:0][63:0] expected_base;
  logic [3:0][31:0] expected_row;
  logic [3:0] legal_mask, expected_error;
  logic [3:0] ar_seen, r_seen, stalled_ar;
  logic [3:0][63:0] retained_ar;
  logic stalled_cfg=0;
  logic [129:0] retained_cfg;
  integer injections=0, cases=0, permutations=0, response_faults=0;
  integer address_faults=0, simultaneous_cases=0, done_count=0;
  integer a,b,c,d,i,k,cycle;
  logic active=0;

  function automatic [127:0] golden(input integer row);
    integer lane;
    reg signed [15:0] value;
    begin
      for (lane=0;lane<8;lane=lane+1) begin
        value=row*8+lane-256;
        golden[lane*16 +: 16]=value;
      end
    end
  endfunction
  task automatic tick;
    begin @(posedge clk); #1; end
  endtask
  task automatic drive_edge;
    begin @(negedge clk); end
  endtask

  always @(posedge clk) begin
    if (!rst && active) begin
      for (integer p=0;p<4;p=p+1) begin
        if (stalled_ar[p] && (!m_axi_arvalid[p] || m_axi_araddr[p] !== retained_ar[p]))
          $fatal(1,"AR retention failed port %0d",p);
        stalled_ar[p]=m_axi_arvalid[p] && !m_axi_arready[p];
        retained_ar[p]=m_axi_araddr[p];
        if (m_axi_arvalid[p]) begin
          if (!legal_mask[p]) $fatal(1,"Illegal address issued port %0d",p);
          if (m_axi_araddr[p] !== expected_base[p]+(64'(expected_row[p])<<4))
            $fatal(1,"Captured address mismatch port %0d",p);
          if (m_axi_arid[p] !== 0 || m_axi_arlen[p] !== 0 ||
              m_axi_arsize[p] !== 4 || m_axi_arburst[p] !== 1 ||
              m_axi_arlock[p] !== 0 || m_axi_arcache[p] !== 3 ||
              m_axi_arprot[p] !== 0 || m_axi_arqos[p] !== 0)
            $fatal(1,"AR attributes mismatch port %0d",p);
        end
        if (m_axi_arvalid[p] && m_axi_arready[p]) begin
          if (ar_seen[p]) $fatal(1,"Duplicate request port %0d",p);
          ar_seen[p]=1;
        end
        if (m_axi_rvalid[p] && m_axi_rready[p]) begin
          if (!ar_seen[p] || r_seen[p]) $fatal(1,"Unexpected response port %0d",p);
          r_seen[p]=1;
        end
      end
      if (stalled_cfg && (!cfg_valid || {cfg_index,cfg_data} !== retained_cfg))
        $fatal(1,"Configuration retention failed");
      stalled_cfg=cfg_valid && !cfg_ready;
      retained_cfg={cfg_index,cfg_data};
      if (cfg_valid) begin
        if (r_seen !== legal_mask || expected_error != 0)
          $fatal(1,"Injected before gather or on failing group");
        if (cfg_index !== injections[1:0] || cfg_data !== golden(expected_row[cfg_index]))
          $fatal(1,"Ordered slot/lane golden mismatch slot %0d",cfg_index);
      end
      if (cfg_valid && cfg_ready) injections=injections+1;
      if (done) done_count=done_count+1;
      if (error_valid && (r_seen !== legal_mask || error_mask !== expected_error ||
                         committed_mask !== 0 || all_loaded || load_ready))
        $fatal(1,"Error published before drain or wrong error state");
    end
  end

  // mode: 0 success, 1 alignment, 2 index, 3 address overflow,
  // 4 RRESP, 5 RID, 6 missing RLAST (single-beat fault detection only).
  task automatic begin_case(input integer mode, input integer bad_port);
    begin
      drive_edge();
      if (!load_ready) $fatal(1,"No-reset restart not ready");
      cfg_ready=0; error_ready=0; m_axi_arready=0;
      m_axi_rvalid=0; m_axi_rresp=0; m_axi_rid=0; m_axi_rlast='1;
      for(integer p=0;p<4;p=p+1) begin
        expected_base[p]=(p==0) ? 0 : 64'h100000000+p*4096+cases*4096;
        expected_row[p]=(cases*7+p*13)%64;
      end
      expected_error=0; legal_mask=15;
      if(mode!=0) expected_error[bad_port]=1;
      if(mode>=1 && mode<=3) legal_mask[bad_port]=0;
      if(mode==1) expected_base[bad_port]=64'h100000003;
      if(mode==2) expected_row[bad_port]=64;
      if(mode==3) begin expected_base[bad_port]=64'hfffffffffffffff0; expected_row[bad_port]=2; end
      table_base_addr=expected_base; lookup_index=expected_row;
      ar_seen=0; r_seen=0; stalled_ar=0; stalled_cfg=0;
      injections=0; done_count=0; active=1; load_valid=1;
      tick(); drive_edge(); load_valid=0;
      // Mutate inputs immediately after capture; independent AR stalls follow.
      table_base_addr='1; lookup_index='1;
      for(integer t=0;t<17;t=t+1) begin
        for(integer p=0;p<4;p=p+1) m_axi_arready[p]=(t>=p*3+2);
        // A busy pulse must not capture the poisoned request.
        load_valid=(t==3 || t==7);
        tick(); drive_edge();
      end
      load_valid=0;
      if(ar_seen !== legal_mask) $fatal(1,"Not all legal ports independently issued");
      if(r_seen != 0 || cfg_valid || error_valid) $fatal(1,"Premature completion");
    end
  endtask

  task automatic respond(input integer port_id, input integer mode, input integer bad_port);
    integer timeout;
    begin
      drive_edge();
      m_axi_rdata[port_id]=golden(expected_row[port_id]);
      m_axi_rresp[port_id]=(port_id==bad_port && mode==4) ? 2 : 0;
      m_axi_rid[port_id]=(port_id==bad_port && mode==5);
      m_axi_rlast[port_id]=!(port_id==bad_port && mode==6);
      m_axi_rvalid[port_id]=1;
      timeout=0;
      while(!r_seen[port_id] && timeout<30) begin tick(); timeout=timeout+1; end
      if(!r_seen[port_id]) $fatal(1,"Response timeout port %0d",port_id);
      drive_edge(); m_axi_rvalid[port_id]=0;
      repeat(3) tick();
    end
  endtask

  task automatic finish_case;
    integer timeout;
    begin
      if(expected_error==0) begin
        timeout=0;
        while(!cfg_valid && timeout<30) begin tick(); timeout=timeout+1; end
        if(!cfg_valid) $fatal(1,"Configuration timeout");
        for(integer slot_id=0;slot_id<4;slot_id=slot_id+1) begin
          repeat(4) tick();
          drive_edge(); load_valid=1; cfg_ready=1;
          tick(); drive_edge(); load_valid=0; cfg_ready=0;
        end
        repeat(4) tick();
        if(!all_loaded || !load_ready || busy || committed_mask !== 15 ||
           injections!=4 || done_count!=1 || error_valid)
          $fatal(1,"Success completion mismatch injections=%0d done=%0d",injections,done_count);
      end else begin
        timeout=0;
        while(!error_valid && timeout<30) begin tick(); timeout=timeout+1; end
        if(!error_valid) $fatal(1,"Error timeout");
        repeat(6) tick();
        if(error_mask !== expected_error || injections!=0 || done_count!=0)
          $fatal(1,"Error retention mismatch");
        drive_edge(); error_ready=1; tick(); drive_edge(); error_ready=0;
        tick();
        if(!load_ready || busy || all_loaded) $fatal(1,"Error recovery failed");
      end
      cases=cases+1;
      // Keep monitor active until the next case, catching duplicate traffic.
      repeat(3) tick();
    end
  endtask

  initial begin
    repeat(5) tick(); drive_edge(); rst=0; tick();
    for(a=0;a<4;a=a+1) for(b=0;b<4;b=b+1)
      for(c=0;c<4;c=c+1) for(d=0;d<4;d=d+1)
        if(a!=b && a!=c && a!=d && b!=c && b!=d && c!=d) begin
          begin_case(0,0);
          respond(a,0,0); respond(b,0,0); respond(c,0,0); respond(d,0,0);
          finish_case(); permutations=permutations+1;
        end
    begin_case(0,0);
    drive_edge();
    for(i=0;i<4;i=i+1) m_axi_rdata[i]=golden(expected_row[i]);
    m_axi_rvalid=15; tick();
    if(r_seen !== 15) $fatal(1,"Simultaneous response not accepted");
    drive_edge(); m_axi_rvalid=0; finish_case(); simultaneous_cases=simultaneous_cases+1;
    for(k=1;k<=6;k=k+1) for(i=0;i<4;i=i+1) begin
      begin_case(k,i);
      if(k>=4) respond(i,k,i);
      // Delayed peers keep the group busy after the failing port completes.
      repeat(12) begin tick(); if(error_valid || load_ready) $fatal(1,"Failed group escaped before drain"); end
      for(integer peer=0;peer<4;peer=peer+1) if(peer!=i) respond(peer,k,i);
      finish_case();
      if(k<=3) address_faults=address_faults+1; else response_faults=response_faults+1;
      // A successful group immediately after every error checks stale state.
      begin_case(0,0); respond(3,0,0); respond(0,0,0); respond(2,0,0); respond(1,0,0); finish_case();
    end
    if(permutations!=24 || address_faults!=12 || response_faults!=12 || cases!=73)
      $fatal(1,"Coverage counts incomplete");
    $display("A17_1_PARALLEL_LOOKUP_CASES=%0d",cases);
    $display("A17_1_RESPONSE_PERMUTATIONS=%0d",permutations);
    $display("A17_1_SIMULTANEOUS_RESPONSE_CASES=%0d",simultaneous_cases);
    $display("A17_1_ADDRESS_ERROR_CASES=%0d",address_faults);
    $display("A17_1_RESPONSE_ERROR_CASES=%0d",response_faults);
    $display("A17_1_PARALLEL_LOOKUP_TEST=PASS");
    $finish;
  end
  initial begin #1000000; $fatal(1,"Global watchdog timeout"); end
endmodule

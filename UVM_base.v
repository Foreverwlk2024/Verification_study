// =================================================================
// 万能 UVM 基础架构模板 (UVM Base Architecture Template)
// 使用说明：全局搜索 "my_" 替换为你的协议名 (如 "axi_", "ahb_")
// =================================================================

import uvm_pkg::*;
`include "uvm_macros.svh"

// -----------------------------------------------------------------
// 1. 物理接口 (Interface)
// -----------------------------------------------------------------
interface my_if(input clk, input rst_n);
    // TODO: 在这里定义你的物理连线 (logic)
endinterface

// -----------------------------------------------------------------
// 2. 事务载荷 (Transaction / Sequence Item)
// -----------------------------------------------------------------
class my_transaction extends uvm_sequence_item;
    // TODO: 声明纯软件的 rand 数据包变量
    rand bit [31:0] data; 

    `uvm_object_utils_begin(my_transaction)
        // TODO: 如果需要自动打印/比较，这里可以用 uvm_field 宏
        `uvm_field_int(data, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "my_transaction");
        super.new(name);
    endfunction
endclass

// -----------------------------------------------------------------
// 3. 基础剧本 (Base Sequence)
// -----------------------------------------------------------------
class my_base_sequence extends uvm_sequence #(my_transaction);
    `uvm_object_utils(my_base_sequence)

    function new(string name = "my_base_sequence");
        super.new(name);
    endfunction

    virtual task body();
        my_transaction req;
        // TODO: 定义发包逻辑
        repeat(10) begin
            req = my_transaction::type_id::create("req");
            start_item(req);
            assert(req.randomize());
            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------
// 4. 驱动器 (Driver)
// -----------------------------------------------------------------
class my_driver extends uvm_driver #(my_transaction);
    `uvm_component_utils(my_driver)
    
    virtual my_if vif;

    function new(string name = "my_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 获取配置库中的物理电缆
        if(!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Failed to get virtual interface!")
    endfunction

    virtual task run_phase(uvm_phase phase);
        my_transaction req;
        // TODO: 初始复位动作
        forever begin
            seq_item_port.get_next_item(req);
            // TODO: 在这里写具体的引脚电平驱动时序 drive_vif(req);
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------
// 5. 监测器 (Monitor)
// -----------------------------------------------------------------
class my_monitor extends uvm_monitor;
    `uvm_component_utils(my_monitor)
    
    virtual my_if vif;
    uvm_analysis_port #(my_transaction) ap;

    function new(string name = "my_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if(!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Failed to get virtual interface!")
    endfunction

    virtual task run_phase(uvm_phase phase);
        my_transaction tr;
        forever begin
            // TODO: 等待总线有效信号 @(posedge vif.clk);
            // 抓取信号并赋值给 tr
            // ap.write(tr);
        end
    endtask
endclass

// -----------------------------------------------------------------
// 6. 代理小队 (Agent)
// -----------------------------------------------------------------
class my_agent extends uvm_agent;
    `uvm_component_utils(my_agent)
    
    my_driver drv;
    uvm_sequencer #(my_transaction) sqr;
    my_monitor mon;

    function new(string name = "my_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv = my_driver::type_id::create("drv", this);
        sqr = uvm_sequencer#(my_transaction)::type_id::create("sqr", this);
        mon = my_monitor::type_id::create("mon", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass

// -----------------------------------------------------------------
// 7. 裁判 (Scoreboard) 
// -----------------------------------------------------------------
class my_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(my_scoreboard)
    
    uvm_analysis_imp #(my_transaction, my_scoreboard) scb_export;

    function new(string name = "my_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        scb_export = new("scb_export", this);
    endfunction

    virtual function void write(my_transaction tr);
        // TODO: 接收到 Monitor 的广播，在这里进行预期值和实际值的比对
    endfunction
endclass

// -----------------------------------------------------------------
// 8. 环境大管家 (Environment)
// -----------------------------------------------------------------
class my_env extends uvm_env;
    `uvm_component_utils(my_env)

    my_agent      agt;
    my_scoreboard scb;
    
    function new(string name = "my_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = my_agent::type_id::create("agt", this);
        scb = my_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.ap.connect(scb.scb_export);
    endfunction
endclass

// -----------------------------------------------------------------
// 9. 最高指挥官 (Testcase)
// -----------------------------------------------------------------
class my_test extends uvm_test;
    `uvm_component_utils(my_test)
    
    my_env env;
    
    function new(string name = "my_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = my_env::type_id::create("env", this); 
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        my_base_sequence seq = my_base_sequence::type_id::create("seq");
        
        phase.raise_objection(this);
        seq.start(env.agt.sqr); 
        phase.drop_objection(this);
    endtask
endclass

// -----------------------------------------------------------------
// 10. 顶层仿真台 (Top Module)
// -----------------------------------------------------------------
module tb_top;
    logic clk;
    logic rst_n;

    // TODO: 生成时钟和复位

    my_if vif(clk, rst_n);
    // TODO: 例化你的 DUT 并连接 vif

    initial begin
        uvm_config_db#(virtual my_if)::set(null, "uvm_test_top.*", "vif", vif);
        run_test("my_test"); 
    end
endmodule
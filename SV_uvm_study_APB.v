/*
    物理层：apb_if.sv (接口电缆)
    UVM 核心层：把所有类按从底向上的顺序打包在一起 
    顶层启动层：tb_top.sv (测试顶层，展示 UVM 是怎么跑起来的)。
*/

//第 1 部分：物理层 (接口定义)---->这是连接纯软件（UVM）和纯硬件（DUT 设计）的实体电缆。
// 文件名: apb_if.sv
interface apb_if(input clk, input rst_n);
    logic [31:0] paddr;
    logic        pwrite;
    logic        psel;
    logic        penable;
    logic [31:0] pwdata;
    logic [31:0] prdata;
endinterface

/*第 2 部分：UVM 核心架构全家桶--->请顺着**“数据包 -> 剧本 -> 驱动/监听 -> 代理 -> 裁判/考勤 -> 环境 -> 测试用例”**的顺序往下读，这就是大厂标准的“自底向上”架构路线！*/

// 必须导入 UVM 魔法库
import uvm_pkg::*;
`include "uvm_macros.svh"

// ==========================================
// 1. 血液 (Transaction)
// ==========================================
class APB_Transaction extends uvm_sequence_item;//纯数据uvm_object
    rand bit [31:0] paddr;
    rand bit        pwrite;
    rand bit [31:0] pwdata;
         bit [31:0] prdata; // 读回来的数据，不需要随机

    `uvm_object_utils(APB_Transaction)

    constraint c_align { soft paddr[1:0] == 2'b00; } // 地址4字节对齐

    function new(string name = "APB_Transaction");
        super.new(name);
    endfunction
endclass

// ==========================================
// 2. 剧本 (Sequence)
// ==========================================
class APB_Unaligned_Seq extends uvm_sequence #(APB_Transaction);
    `uvm_object_utils(APB_Unaligned_Seq)

    function new(string name = "APB_Unaligned_Seq");
        super.new(name);
    endfunction

    task body();
        APB_Transaction req;
        req = new("req"); // 1. 造车，创建对象
        
        //申请发送——向sequencer请求发送一个sequence item（事务）；它本身并不发送数据，而是获取发送权限
        //向 sequencer 请求发送权限，会阻塞直到获得授权。这是 sequence 与 sequencer 握手的起点。
        start_item(req); 
        // 3. 掷骰子，并强行注入非对齐地址报错
        assert(req.randomize() with { paddr == 32'h0000_0003; }); 
        finish_item(req); // 4. 确认发送并等待 Driver回执
    endtask
endclass

// ==========================================
// 3. 苦力搬运工 (Driver)
// ==========================================
class APB_Driver extends uvm_driver #(APB_Transaction);
    `uvm_component_utils(APB_Driver)
    
    virtual apb_if vif; // 声明虚拟电缆

    function new(string name = "APB_Driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // 在建房阶段，从大管家的配置库里拿到真实的物理电缆 (UVM 必备魔法)
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))//get()有返回值，成功返回1
            `uvm_fatal("DRV", "Driver 没有拿到物理接口 vif！")
            //使用 uvm_config_db::get 从配置库中获取虚拟接口，存入 vif。如果获取失败，用 `uvm_fatal 报告致命错误并终止仿真。
            //工业界防呆设计，build_phase里都绝对会有这两行代码的护体
    endfunction

    task run_phase(uvm_phase phase);
        APB_Transaction req;
        forever begin
            seq_item_port.get_next_item(req); // 伸手拿包
            drive_pkt(req);                   // 执行物理驱动
            seq_item_port.item_done();        // 给回执
        end
    endtask

    // 物理层时序动作--模拟apb协议的时序
    task drive_pkt(APB_Transaction Tr);
        @(posedge vif.clk);  // Setup Phase
        vif.psel    <= 1;
        vif.penable <= 0;
        vif.paddr   <= Tr.paddr;
        vif.pwrite  <= Tr.pwrite;
        if (Tr.pwrite == 1) vif.pwdata <= Tr.pwdata;

        @(posedge vif.clk);  // Access Phase
        vif.penable <= 1;

        @(posedge vif.clk);  // 结束与采样阶段
        if (Tr.pwrite == 0) Tr.prdata = vif.prdata;
        vif.psel    <= 0;
        vif.penable <= 0;
    endtask
endclass

// ==========================================
// 4. 潜伏窃听器 (Monitor)
// ==========================================
class APB_Monitor extends uvm_monitor;
    `uvm_component_utils(APB_Monitor)
    
    virtual apb_if vif;
    uvm_analysis_port #(APB_Transaction) ap; // 声明一个分析端口，用于将监测到的事务发送给所有连接的组件

    function new(string name = "APB_Monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this); // 造出大喇叭
        if(!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Monitor 没有拿到物理接口 vif！")
    endfunction

    task run_phase(uvm_phase phase);
        APB_Transaction t;
        forever begin
            @(posedge vif.clk);
            if (vif.psel == 1 && vif.penable == 1) begin
                t = new("t");
                t.paddr  = vif.paddr;
                t.pwrite = vif.pwrite;
                if (vif.pwrite == 1) t.pwdata = vif.pwdata;
                else                 t.prdata = vif.prdata;
                
                ap.write(t); // 调用 ap.write(t) 将事务广播出去！
                `uvm_info("MON", $sformatf("抓到传输: 地址=%0h, 读写=%0b", t.paddr, t.pwrite), UVM_LOW)
            end
        end
    endtask
endclass

// ==========================================
// 5. 特种兵小队 (Agent)
// ==========================================
class APB_Agent extends uvm_agent;
    `uvm_component_utils(APB_Agent)
    
    APB_Driver drv;
    uvm_sequencer #(APB_Transaction) sqr; // 官方模具直接用
    APB_Monitor mon;

    function new(string name = "APB_Agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv = APB_Driver::type_id::create("drv", this);
        sqr = uvm_sequencer#(APB_Transaction)::type_id::create("sqr", this);
        mon = APB_Monitor::type_id::create("mon", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Driver 的接包端 连上 Sequencer 的发包端
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass

// ==========================================
// 6. 裁判 (Scoreboard) & 考勤 (Coverage)
// ==========================================
class APB_Scoreboard extends uvm_scoreboard;
    `uvm_component_utils(APB_Scoreboard)
    
    uvm_analysis_imp #(APB_Transaction, APB_Scoreboard) apb_export;

    function new(string name = "APB_Scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_export = new("apb_export", this); // 造出接收端
    endfunction

    // 听到大喇叭自动执行
    virtual function void write(APB_Transaction tr);
        if (tr.pwrite == 0) begin
            if (tr.prdata !== 32'h0)
                `uvm_error("SCB", $sformatf("数据比对失败！地址 %0h 读出值 %0h", tr.paddr, tr.prdata))
            else
                `uvm_info("SCB", "比对通过！", UVM_LOW)
        end
    endfunction
endclass

class APB_Coverage extends uvm_subscriber #(APB_Transaction);
    `uvm_component_utils(APB_Coverage)
    
    APB_Transaction tr_clone;

    covergroup cg_apb;
        cp_pwrite: coverpoint tr_clone.pwrite {
            bins read_op  = {0};
            bins write_op = {1};
        }
    endgroup

    function new(string name = "APB_Coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_apb = new();
    endfunction

    // 听到大喇叭自动执行
    virtual function void write(APB_Transaction t);
        tr_clone = t;
        cg_apb.sample(); // 打卡
    endfunction
endclass

// ==========================================
// 7. 大管家 (Environment)
// ==========================================
class APB_Env extends uvm_env;
    `uvm_component_utils(APB_Env)

    APB_Agent      agt;
    APB_Scoreboard scb;
    APB_Coverage   cov;
    
    function new(string name = "APB_Env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = APB_Agent::type_id::create("agt", this);
        scb = APB_Scoreboard::type_id::create("scb", this);
        cov = APB_Coverage::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // 大喇叭一呼百应！
        agt.mon.ap.connect(scb.apb_export);
        agt.mon.ap.connect(cov.analysis_export);
        //将 monitor 的 analysis_port 连接到 scoreboard 的 analysis_imp 和 coverage 的 analysis_export
    endfunction
endclass

// ==========================================
// 8. 最高指挥官 (Testcase)
// ==========================================
class APB_Test extends uvm_test;
    `uvm_component_utils(APB_Test)
    
    APB_Env env;
    
    function new(string name = "APB_Test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = APB_Env::type_id::create("env", this); 
    endfunction
    
    task run_phase(uvm_phase phase);
        APB_Unaligned_Seq seq = new("seq");
        
        phase.raise_objection(this); // 提起 objection，激励开始。
        seq.start(env.agt.sqr);      // 在指定的 sequencer 上启动 sequence
        phase.drop_objection(this);  // 撤销 objection，表示激励完成
    endtask
endclass

//第 3 部分：点火发射台 (Top Module)----->这是一个普通的 Verilog module，它是所有软硬件一切的发源地。

// 文件名: tb_top.sv
module tb_top;

    import uvm_pkg::*;

    // 1. 生成物理时钟和复位
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz 时钟
    end

    initial begin
        rst_n = 0;
        #20 rst_n = 1;
    end

    // 2. 实例化物理接口电缆
    apb_if vif(clk, rst_n);

    // 3. 实例化你的待测芯片 DUT (这里略过具体的连线)
    // your_apb_router_dut dut( ... ); 

    // 4. 【核心启动魔法】
    initial begin
        // 把物理电缆 vif 存进大管家的云端配置库 (Config DB)
        // 这样 Driver 和 Monitor 就能在 build_phase 里用 get() 拿到了！
        uvm_config_db#(virtual apb_if)::set(null, "uvm_test_top.*", "vif", vif);

        // 呼叫最高指挥官，一键启动 UVM 测试框架！
        run_test("APB_Test"); 
    end

endmodule
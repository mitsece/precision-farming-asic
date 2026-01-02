/*
 * Precision Farming ASIC - Optimized for 1x1 Tile
 * 
 * Balanced design with moderate complexity:
 * 1. Dual Sensor Monitoring with averaging
 * 2. ML Harvest Detection with color classification
 * 3. Auto irrigation control
 */

`default_nettype none

module tt_um_precision_farming (
    input  wire [7:0] ui_in,    // Sensor data / Camera pixels
    output wire [7:0] uo_out,   // Status and control outputs
    input  wire [7:0] uio_in,   // Control inputs
    output wire [7:0] uio_out,  // Debug/Status outputs
    output wire [7:0] uio_oe,   // IO Enable
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    // I/O Configuration
    assign uio_oe = 8'b11000000; // Bits 6-7 as outputs
    
    // Control signal decoding
    wire mode_ml = uio_in[7];           // 0=Sensor mode, 1=ML mode
    wire vsync = uio_in[6];             // Frame sync
    wire href = uio_in[5];              // Line valid
    wire auto_mode = uio_in[4];         // Auto control
    wire sensor_sel = uio_in[0];        // Which sensor (0 or 1)
    
    // Output signals
    reg [1:0] actuator_control;         // Pump, valve
    reg [1:0] alert_level;              // Alert severity
    
    assign uio_out = {actuator_control, 4'b0, alert_level};
    
    // Main output
    reg [7:0] status_output;
    assign uo_out = status_output;

    // ============================================
    // SENSOR MONITORING MODE - 2 Channels
    // ============================================
    
    // 2 sensor channels with 4-sample history
    reg [7:0] sensor_history_0_0, sensor_history_0_1, sensor_history_0_2, sensor_history_0_3;
    reg [7:0] sensor_history_1_0, sensor_history_1_1, sensor_history_1_2, sensor_history_1_3;
    reg [1:0] history_ptr_0, history_ptr_1;
    reg [9:0] sensor_sum_0, sensor_sum_1;
    reg [7:0] sensor_avg_0, sensor_avg_1;
    reg [7:0] sensor_threshold_0, sensor_threshold_1;
    
    // State counter
    reg [2:0] sample_state;
    
    // ============================================
    // ML MODE - Simplified
    // ============================================
    
    // Pixel counters
    reg [11:0] green_pixel_count;
    reg [11:0] red_pixel_count;
    reg [11:0] total_pixel_count;
    
    // Neural network (2 neurons)
    reg [11:0] hidden_neuron1;
    reg [11:0] hidden_neuron2;
    
    // Outputs
    reg [7:0] output_neuron;
    reg harvest_ready;
    reg pest_detected;
    
    // Frame state
    reg [1:0] frame_state;
    
    // ============================================
    // CONTROL
    // ============================================
    
    reg pump_on;
    reg valve_open;
    reg [11:0] pump_timer;
    
    // Helper wires for array access
    reg [7:0] current_history_value;
    
    always @(*) begin
        // Read from history based on sensor_sel and history_ptr
        if (sensor_sel == 0) begin
            case (history_ptr_0)
                2'd0: current_history_value = sensor_history_0_0;
                2'd1: current_history_value = sensor_history_0_1;
                2'd2: current_history_value = sensor_history_0_2;
                2'd3: current_history_value = sensor_history_0_3;
            endcase
        end else begin
            case (history_ptr_1)
                2'd0: current_history_value = sensor_history_1_0;
                2'd1: current_history_value = sensor_history_1_1;
                2'd2: current_history_value = sensor_history_1_2;
                2'd3: current_history_value = sensor_history_1_3;
            endcase
        end
    end
    
    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset sensor 0 history
            sensor_history_0_0 <= 0;
            sensor_history_0_1 <= 0;
            sensor_history_0_2 <= 0;
            sensor_history_0_3 <= 0;
            history_ptr_0 <= 0;
            sensor_sum_0 <= 0;
            sensor_avg_0 <= 0;
            sensor_threshold_0 <= 128;
            
            // Reset sensor 1 history
            sensor_history_1_0 <= 0;
            sensor_history_1_1 <= 0;
            sensor_history_1_2 <= 0;
            sensor_history_1_3 <= 0;
            history_ptr_1 <= 0;
            sensor_sum_1 <= 0;
            sensor_avg_1 <= 0;
            sensor_threshold_1 <= 128;
            
            // Reset ML
            green_pixel_count <= 0;
            red_pixel_count <= 0;
            total_pixel_count <= 0;
            hidden_neuron1 <= 0;
            hidden_neuron2 <= 0;
            output_neuron <= 0;
            harvest_ready <= 0;
            pest_detected <= 0;
            
            // Reset control
            pump_on <= 0;
            valve_open <= 0;
            actuator_control <= 0;
            alert_level <= 0;
            sample_state <= 0;
            frame_state <= 0;
            pump_timer <= 0;
            status_output <= 0;
            
        end else if (ena) begin
            
            if (!mode_ml) begin
                // ============================================
                // SENSOR MODE
                // ============================================
                
                // Store reading in history
                if (sensor_sel == 0) begin
                    case (history_ptr_0)
                        2'd0: sensor_history_0_0 <= ui_in;
                        2'd1: sensor_history_0_1 <= ui_in;
                        2'd2: sensor_history_0_2 <= ui_in;
                        2'd3: sensor_history_0_3 <= ui_in;
                    endcase
                    history_ptr_0 <= history_ptr_0 + 1;
                    
                    // Running sum (4 samples)
                    sensor_sum_0 <= sensor_sum_0 - {2'b0, current_history_value} + {2'b0, ui_in};
                    
                    // Average: divide by 4
                    sensor_avg_0 <= {2'b0, sensor_sum_0[9:2]};
                    
                end else begin
                    case (history_ptr_1)
                        2'd0: sensor_history_1_0 <= ui_in;
                        2'd1: sensor_history_1_1 <= ui_in;
                        2'd2: sensor_history_1_2 <= ui_in;
                        2'd3: sensor_history_1_3 <= ui_in;
                    endcase
                    history_ptr_1 <= history_ptr_1 + 1;
                    
                    // Running sum (4 samples)
                    sensor_sum_1 <= sensor_sum_1 - {2'b0, current_history_value} + {2'b0, ui_in};
                    
                    // Average: divide by 4
                    sensor_avg_1 <= {2'b0, sensor_sum_1[9:2]};
                end
                
                // Decision logic
                sample_state <= sample_state + 1;
                if (sample_state == 7) begin
                    // Check sensors
                    if (sensor_avg_0 > sensor_threshold_0 && sensor_avg_1 > sensor_threshold_1) begin
                        alert_level <= 2'b11;
                    end else if (sensor_avg_0 > sensor_threshold_0 || sensor_avg_1 > sensor_threshold_1) begin
                        alert_level <= 2'b01;
                    end else begin
                        alert_level <= 2'b00;
                    end
                    
                    // Auto control
                    if (auto_mode) begin
                        if (sensor_avg_0 < 80) begin
                            pump_on <= 1;
                            valve_open <= 1;
                            pump_timer <= 12'd1000;
                        end else if (sensor_avg_0 > 180) begin
                            pump_on <= 0;
                            valve_open <= 0;
                        end
                    end
                end
                
                // Timer countdown
                if (pump_timer > 0) begin
                    pump_timer <= pump_timer - 1;
                    if (pump_timer == 1) begin
                        pump_on <= 0;
                        valve_open <= 0;
                    end
                end
                
                // Output
                status_output <= {alert_level, 4'b0, pump_on, valve_open};
                
            end else begin
                // ============================================
                // ML MODE
                // ============================================
                
                if (vsync) begin
                    // Reset for new frame
                    green_pixel_count <= 0;
                    red_pixel_count <= 0;
                    total_pixel_count <= 0;
                    frame_state <= 0;
                    
                end else if (href) begin
                    // Process pixel
                    total_pixel_count <= total_pixel_count + 1;
                    
                    // Color detection (RRR GGG BB)
                    if ((ui_in[4:2] > 3'b100) && (ui_in[7:5] < 3'b011)) begin
                        green_pixel_count <= green_pixel_count + 1;
                    end else if (ui_in[7:5] > 3'b100) begin
                        red_pixel_count <= red_pixel_count + 1;
                    end
                    
                    frame_state <= 1;
                    
                end else if (frame_state == 1 && !href) begin
                    // Frame end - compute
                    hidden_neuron1 <= green_pixel_count;
                    hidden_neuron2 <= red_pixel_count;
                    frame_state <= 2;
                    
                end else if (frame_state == 2) begin
                    // Decision
                    // Fix: Cannot bit-slice arithmetic result directly
                    output_neuron <= hidden_neuron1[7:0] + hidden_neuron2[7:0];
                    
                    if (hidden_neuron1 > (total_pixel_count >> 2)) begin
                        harvest_ready <= 0;
                    end else if (hidden_neuron2 > (total_pixel_count >> 3)) begin
                        harvest_ready <= 1;
                    end
                    
                    if (red_pixel_count > (green_pixel_count << 1)) begin
                        pest_detected <= 1;
                    end else begin
                        pest_detected <= 0;
                    end
                    
                    frame_state <= 3;
                end
                
                // Output
                status_output <= {harvest_ready, pest_detected, output_neuron[5:0]};
            end
            
            // Actuator update
            actuator_control <= {valve_open, pump_on};
        end
    end

    // Suppress unused warnings
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, uio_in[3:1], 1'b0};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule

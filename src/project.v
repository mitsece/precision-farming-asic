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
    reg [7:0] sensor_history [0:1][0:3]; // 2 sensors, 4 samples each
    reg [1:0] history_ptr [0:1];         // Write pointer
    reg [9:0] sensor_sum [0:1];          // Running sum
    reg [7:0] sensor_avg [0:1];          // Current average
    reg [7:0] sensor_threshold [0:1];    // Thresholds
    
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
    
    integer i, j;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset sensor data
            for (i = 0; i < 2; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    sensor_history[i][j] <= 0;
                end
                history_ptr[i] <= 0;
                sensor_sum[i] <= 0;
                sensor_avg[i] <= 0;
                sensor_threshold[i] <= 128;
            end
            
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
                
                // Store reading
                sensor_history[sensor_sel][history_ptr[sensor_sel]] <= ui_in;
                history_ptr[sensor_sel] <= history_ptr[sensor_sel] + 1;
                
                // Running sum (4 samples)
                sensor_sum[sensor_sel] <= sensor_sum[sensor_sel] - 
                    {2'b0, sensor_history[sensor_sel][history_ptr[sensor_sel]]} + 
                    {2'b0, ui_in};
                
                // Average: divide by 4
                sensor_avg[sensor_sel] <= {2'b0, sensor_sum[sensor_sel][9:2]};
                
                // Decision logic
                sample_state <= sample_state + 1;
                if (sample_state == 7) begin
                    // Check sensors
                    alert_level <= 0;
                    if (sensor_avg[0] > sensor_threshold[0]) alert_level <= alert_level + 1;
                    if (sensor_avg[1] > sensor_threshold[1]) alert_level <= alert_level + 1;
                    
                    // Auto control
                    if (auto_mode) begin
                        if (sensor_avg[0] < 80) begin
                            pump_on <= 1;
                            valve_open <= 1;
                            pump_timer <= 12'd1000;
                        end else if (sensor_avg[0] > 180) begin
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
                    output_neuron <= (hidden_neuron1 + hidden_neuron2)[7:0];
                    
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

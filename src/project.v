/*
 * Precision Farming ASIC - Microgreen Growth Monitor
 * Optimized for 1x2 Tiny Tapeout Tile
 * 
 * Application: Pea Plant Microgreen Cultivation
 * - 4 Environmental Sensors (Soil, Temp, Humidity, Light)
 * - Camera-based Growth Detection
 * - Multi-threshold Alert System
 * - Harvest Readiness Detection
 */

`default_nettype none

module tt_um_precision_farming (
    input  wire [7:0] ui_in,    // Sensor data / Camera pixels
    output wire [7:0] uo_out,   // Status and alerts
    input  wire [7:0] uio_in,   // Control inputs
    output wire [7:0] uio_out,  // Debug/Extended outputs
    output wire [7:0] uio_oe,   // IO Enable
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    // ============================================
    // I/O CONFIGURATION
    // ============================================
    assign uio_oe = 8'b11111111; // All bidirectional pins as outputs
    
    // ============================================
    // CONTROL SIGNAL DECODING
    // ============================================
    wire mode_camera = uio_in[7];       // 0=Sensor mode, 1=Camera mode
    wire vsync = uio_in[6];             // Camera frame sync
    wire href = uio_in[5];              // Camera line valid
    wire [1:0] sensor_sel = uio_in[1:0]; // Sensor selection (0-3)
    // uio_in[4:2] reserved for future use
    
    // ============================================
    // SENSOR THRESHOLDS (Optimized for Pea Microgreens)
    // ============================================
    // Based on typical microgreen growing conditions:
    // - Soil: 60-80% moisture (153-204 in 0-255 scale)
    // - Temp: 18-24°C (scaled to 0-255)
    // - Humidity: 50-70% (128-179 in 0-255 scale)
    // - Light: 12-16 hours/day, moderate intensity
    
    localparam [7:0] SOIL_MIN = 8'd140;      // Below = too dry
    localparam [7:0] SOIL_MAX = 8'd210;      // Above = too wet
    localparam [7:0] TEMP_MIN = 8'd100;      // Below = too cold
    localparam [7:0] TEMP_MAX = 8'd160;      // Above = too hot
    localparam [7:0] HUMID_MIN = 8'd120;     // Below = too dry
    localparam [7:0] HUMID_MAX = 8'd190;     // Above = too humid
    localparam [7:0] LIGHT_MIN = 8'd80;      // Below = too dark
    localparam [7:0] LIGHT_MAX = 8'd220;     // Above = too bright
    
    // ============================================
    // SENSOR MODE REGISTERS
    // ============================================
    reg [7:0] sensor_soil;          // Latest soil moisture reading
    reg [7:0] sensor_temp;          // Latest temperature reading
    reg [7:0] sensor_humid;         // Latest humidity reading
    reg [7:0] sensor_light;         // Latest light reading
    
    // Alert flags for each sensor
    reg alert_soil;
    reg alert_temp;
    reg alert_humid;
    reg alert_light;
    
    // 4-sample averaging for stability
    reg [7:0] soil_history [0:3];
    reg [7:0] temp_history [0:3];
    reg [7:0] humid_history [0:3];
    reg [7:0] light_history [0:3];
    reg [1:0] history_index;
    
    reg [9:0] soil_sum;
    reg [9:0] temp_sum;
    reg [9:0] humid_sum;
    reg [9:0] light_sum;
    
    // ============================================
    // CAMERA MODE REGISTERS (Growth Detection)
    // ============================================
    reg [11:0] green_pixel_count;   // Green pixels (immature)
    reg [11:0] yellow_pixel_count;  // Yellow/mature pixels
    reg [11:0] total_pixel_count;   // Total pixels processed
    
    reg growth_ready;               // Harvest readiness flag
    reg [2:0] growth_stage;         // 0-7 growth stages
    
    // ============================================
    // OUTPUT REGISTERS
    // ============================================
    reg buzzer_active;              // Master alert/buzzer
    reg [3:0] alert_code;           // Which sensors triggered
    reg [7:0] status_output;
    reg [7:0] debug_output;
    
    // ============================================
    // MAIN LOGIC
    // ============================================
    
    integer i;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset all sensor values
            sensor_soil <= 0;
            sensor_temp <= 0;
            sensor_humid <= 0;
            sensor_light <= 0;
            
            // Reset alerts
            alert_soil <= 0;
            alert_temp <= 0;
            alert_humid <= 0;
            alert_light <= 0;
            buzzer_active <= 0;
            alert_code <= 0;
            
            // Reset history
            for (i = 0; i < 4; i = i + 1) begin
                soil_history[i] <= 0;
                temp_history[i] <= 0;
                humid_history[i] <= 0;
                light_history[i] <= 0;
            end
            history_index <= 0;
            
            soil_sum <= 0;
            temp_sum <= 0;
            humid_sum <= 0;
            light_sum <= 0;
            
            // Reset camera
            green_pixel_count <= 0;
            yellow_pixel_count <= 0;
            total_pixel_count <= 0;
            growth_ready <= 0;
            growth_stage <= 0;
            
            status_output <= 0;
            debug_output <= 0;
            
        end else if (ena) begin
            
            if (!mode_camera) begin
                // ============================================
                // SENSOR MONITORING MODE
                // ============================================
                
                // Store new reading in history buffer
                case (sensor_sel)
                    2'b00: begin // Soil moisture
                        soil_history[history_index] <= ui_in;
                        soil_sum <= soil_sum - {2'b0, soil_history[history_index]} + {2'b0, ui_in};
                        sensor_soil <= soil_sum[9:2]; // Divide by 4 for average
                        
                        // Check thresholds
                        if (sensor_soil < SOIL_MIN || sensor_soil > SOIL_MAX) begin
                            alert_soil <= 1;
                        end else begin
                            alert_soil <= 0;
                        end
                    end
                    
                    2'b01: begin // Temperature
                        temp_history[history_index] <= ui_in;
                        temp_sum <= temp_sum - {2'b0, temp_history[history_index]} + {2'b0, ui_in};
                        sensor_temp <= temp_sum[9:2];
                        
                        if (sensor_temp < TEMP_MIN || sensor_temp > TEMP_MAX) begin
                            alert_temp <= 1;
                        end else begin
                            alert_temp <= 0;
                        end
                    end
                    
                    2'b10: begin // Humidity
                        humid_history[history_index] <= ui_in;
                        humid_sum <= humid_sum - {2'b0, humid_history[history_index]} + {2'b0, ui_in};
                        sensor_humid <= humid_sum[9:2];
                        
                        if (sensor_humid < HUMID_MIN || sensor_humid > HUMID_MAX) begin
                            alert_humid <= 1;
                        end else begin
                            alert_humid <= 0;
                        end
                    end
                    
                    2'b11: begin // Light
                        light_history[history_index] <= ui_in;
                        light_sum <= light_sum - {2'b0, light_history[history_index]} + {2'b0, ui_in};
                        sensor_light <= light_sum[9:2];
                        
                        if (sensor_light < LIGHT_MIN || sensor_light > LIGHT_MAX) begin
                            alert_light <= 1;
                        end else begin
                            alert_light <= 0;
                        end
                    end
                endcase
                
                // Increment history pointer
                history_index <= history_index + 1;
                
                // Aggregate alerts
                alert_code <= {alert_light, alert_humid, alert_temp, alert_soil};
                buzzer_active <= alert_soil | alert_temp | alert_humid | alert_light;
                
                // Output current sensor reading
                case (sensor_sel)
                    2'b00: status_output <= sensor_soil;
                    2'b01: status_output <= sensor_temp;
                    2'b10: status_output <= sensor_humid;
                    2'b11: status_output <= sensor_light;
                endcase
                
                debug_output <= {alert_code, sensor_sel, 2'b00};
                
            end else begin
                // ============================================
                // CAMERA MODE (Growth Detection)
                // ============================================
                
                if (vsync) begin
                    // Start of new frame - reset counters
                    green_pixel_count <= 0;
                    yellow_pixel_count <= 0;
                    total_pixel_count <= 0;
                    
                end else if (href) begin
                    // Valid pixel data
                    total_pixel_count <= total_pixel_count + 1;
                    
                    // Color classification (RGB332 or similar format)
                    // Green: High G, Low R,B (immature microgreen)
                    // Yellow/Brown: High R,G, Low B (mature/ready)
                    
                    // Green detection: G[4:2] > 5, R[7:5] < 3
                    if ((ui_in[4:2] > 3'd5) && (ui_in[7:5] < 3'd3)) begin
                        green_pixel_count <= green_pixel_count + 1;
                    end
                    
                    // Yellow/mature detection: R[7:5] > 4, G[4:2] > 3
                    else if ((ui_in[7:5] > 3'd4) && (ui_in[4:2] > 3'd3)) begin
                        yellow_pixel_count <= yellow_pixel_count + 1;
                    end
                    
                end else if (total_pixel_count > 12'd100) begin
                    // Frame complete - analyze results
                    
                    // Calculate growth stage (0-7)
                    // Based on ratio of mature to total pixels
                    if (yellow_pixel_count > (total_pixel_count >> 1)) begin
                        growth_stage <= 3'd7; // Fully mature
                        growth_ready <= 1;
                    end else if (yellow_pixel_count > (total_pixel_count >> 2)) begin
                        growth_stage <= 3'd5; // Nearly ready
                        growth_ready <= 1;
                    end else if (yellow_pixel_count > (total_pixel_count >> 3)) begin
                        growth_stage <= 3'd3; // Mid-growth
                        growth_ready <= 0;
                    end else begin
                        growth_stage <= 3'd1; // Early growth
                        growth_ready <= 0;
                    end
                    
                    // Buzzer for harvest ready
                    buzzer_active <= growth_ready;
                end
                
                // Output growth status
                status_output <= {growth_ready, growth_stage, alert_code};
                debug_output <= yellow_pixel_count[7:0];
            end
        end
    end
    
    // ============================================
    // OUTPUT ASSIGNMENTS
    // ============================================
    assign uo_out = {buzzer_active, status_output[6:0]};
    assign uio_out = debug_output;
    
    // Suppress unused signal warnings
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, uio_in[4:2], green_pixel_count[11:8], 
                     yellow_pixel_count[11:8], total_pixel_count[11:8], 1'b0};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule

// SPDX-FileCopyrightText: © 2024 Tiny Tapeout
// SPDX-License-Identifier: Apache-2.0

/*
 * Precision Farming ASIC - Microgreen Growth Monitor
 * Optimized for 2x2 Tiny Tapeout Tile
 *
 * Application: Pea Plant Microgreen Cultivation
 * - 4 Environmental Sensors (Soil, Temp, Humidity, Light)
 * - Camera-based Growth Detection
 * - Multi-threshold Alert System
 * - Harvest Readiness Detection
 */

`timescale 1ns / 1ps
`default_nettype none

// Suppress TIMESCALEMOD warnings from Sky130 standard cell library
/* verilator lint_off TIMESCALEMOD */

module tt_um_precision_farming (
    input  wire [7:0] ui_in,    // Sensor data / Camera pixels
    output wire [7:0] uo_out,   // Status and alerts
    input  wire [7:0] uio_in,   // Control inputs (ALL INPUTS)
    output wire [7:0] uio_out,  // Not used - tied to 0
    output wire [7:0] uio_oe,   // IO Enable - all inputs
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ============================================
    // I/O CONFIGURATION - CORRECTED
    // ============================================
    // uio_oe bits: 1 = OUTPUT (we drive), 0 = INPUT (we read)
    // All bidirectional pins are INPUTS for control signals
    assign uio_oe  = 8'b00000000;  // All pins configured as INPUTS
    assign uio_out = 8'b00000000;  // Output drivers tied low (not used)

    // ============================================
    // CONTROL SIGNAL DECODING
    // ============================================
    wire       mode_camera = uio_in[7];     // 0=Sensor mode, 1=Camera mode
    wire       vsync       = uio_in[6];     // Camera frame sync
    wire       href        = uio_in[5];     // Camera line valid
    wire [1:0] sensor_sel  = uio_in[1:0];   // Sensor selection (0-3)
    // uio_in[4:2] reserved for future use

    // ============================================
    // SENSOR THRESHOLDS (Optimized for Pea Microgreens)
    // ============================================
    // Based on typical microgreen growing conditions:
    // - Soil: 60-80% moisture (153-204 in 0-255 scale)
    // - Temp: 18-24°C (scaled to 0-255)
    // - Humidity: 50-70% (128-179 in 0-255 scale)
    // - Light: 12-16 hours/day, moderate intensity
    localparam [7:0] SOIL_MIN  = 8'd140;  // Below = too dry
    localparam [7:0] SOIL_MAX  = 8'd210;  // Above = too wet
    localparam [7:0] TEMP_MIN  = 8'd100;  // Below = too cold
    localparam [7:0] TEMP_MAX  = 8'd160;  // Above = too hot
    localparam [7:0] HUMID_MIN = 8'd120;  // Below = too dry
    localparam [7:0] HUMID_MAX = 8'd190;  // Above = too humid
    localparam [7:0] LIGHT_MIN = 8'd80;   // Below = too dark
    localparam [7:0] LIGHT_MAX = 8'd220;  // Above = too bright

    // ============================================
    // SENSOR MODE REGISTERS
    // ============================================
    reg [7:0] sensor_soil;   // Latest soil moisture reading
    reg [7:0] sensor_temp;   // Latest temperature reading
    reg [7:0] sensor_humid;  // Latest humidity reading
    reg [7:0] sensor_light;  // Latest light reading

    // Alert flags for each sensor
    reg alert_soil;
    reg alert_temp;
    reg alert_humid;
    reg alert_light;

    // 4-sample averaging for stability
    reg [7:0] soil_history  [0:3];
    reg [7:0] temp_history  [0:3];
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
    reg        growth_ready;        // Harvest readiness flag
    reg [2:0]  growth_stage;        // 0-7 growth stages
    reg [7:0]  maturity_percent;    // Maturity percentage (0-100)
    reg [11:0] total_green;         // Total green pixels (light + deep)

    // ============================================
    // FAULT DETECTION REGISTERS
    // ============================================
    reg [7:0] last_soil_reading;   // Previous reading for stuck detection
    reg [7:0] last_temp_reading;
    reg [7:0] last_humid_reading;
    reg [7:0] last_light_reading;

    reg fault_soil_stuck;    // Sensor stuck (same value)
    reg fault_temp_stuck;
    reg fault_humid_stuck;
    reg fault_light_stuck;

    reg fault_soil_extreme;  // Extreme/impossible values
    reg fault_temp_extreme;
    reg fault_humid_extreme;
    reg fault_light_extreme;

    // ============================================
    // OUTPUT REGISTERS
    // ============================================
    reg        buzzer_active;   // Master alert/buzzer
    reg [3:0]  alert_code;      // Which sensors triggered
    reg [3:0]  fault_code;      // Which sensors faulted
    reg [7:0]  status_output;

    // ============================================
    // MAIN LOGIC
    // ============================================
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset all sensor values
            sensor_soil  <= 0;
            sensor_temp  <= 0;
            sensor_humid <= 0;
            sensor_light <= 0;

            // Reset alerts
            alert_soil   <= 0;
            alert_temp   <= 0;
            alert_humid  <= 0;
            alert_light  <= 0;
            buzzer_active <= 0;
            alert_code   <= 0;

            // Reset history
            for (i = 0; i < 4; i = i + 1) begin
                soil_history[i]  <= 0;
                temp_history[i]  <= 0;
                humid_history[i] <= 0;
                light_history[i] <= 0;
            end
            history_index <= 0;

            soil_sum  <= 0;
            temp_sum  <= 0;
            humid_sum <= 0;
            light_sum <= 0;

            // Reset camera
            green_pixel_count  <= 0;
            yellow_pixel_count <= 0;
            total_pixel_count  <= 0;
            growth_ready       <= 0;
            growth_stage       <= 0;
            maturity_percent   <= 0;
            total_green        <= 0;

            // Reset fault detection
            last_soil_reading  <= 0;
            last_temp_reading  <= 0;
            last_humid_reading <= 0;
            last_light_reading <= 0;
            fault_soil_stuck   <= 0;
            fault_temp_stuck   <= 0;
            fault_humid_stuck  <= 0;
            fault_light_stuck  <= 0;
            fault_soil_extreme <= 0;
            fault_temp_extreme <= 0;
            fault_humid_extreme <= 0;
            fault_light_extreme <= 0;
            fault_code <= 0;

            status_output <= 0;

        end else if (ena) begin

            if (!mode_camera) begin
                // ============================================
                // SENSOR MONITORING MODE
                // ============================================
                
                // Store new reading in history buffer
                case (sensor_sel)
                    2'b00: begin  // Soil moisture
                        soil_history[history_index] <= ui_in;
                        soil_sum <= soil_sum - {2'b0, soil_history[history_index]} + {2'b0, ui_in};
                        sensor_soil <= soil_sum[9:2];  // Divide by 4 for average
                    end
                    2'b01: begin  // Temperature
                        temp_history[history_index] <= ui_in;
                        temp_sum <= temp_sum - {2'b0, temp_history[history_index]} + {2'b0, ui_in};
                        sensor_temp <= temp_sum[9:2];
                    end
                    2'b10: begin  // Humidity
                        humid_history[history_index] <= ui_in;
                        humid_sum <= humid_sum - {2'b0, humid_history[history_index]} + {2'b0, ui_in};
                        sensor_humid <= humid_sum[9:2];
                    end
                    2'b11: begin  // Light
                        light_history[history_index] <= ui_in;
                        light_sum <= light_sum - {2'b0, light_history[history_index]} + {2'b0, ui_in};
                        sensor_light <= light_sum[9:2];
                    end
                endcase

                // Increment history pointer
                history_index <= history_index + 1;

                // ============================================
                // THRESHOLD CHECKING
                // ============================================
                alert_soil  <= (sensor_soil < SOIL_MIN)   || (sensor_soil > SOIL_MAX);
                alert_temp  <= (sensor_temp < TEMP_MIN)   || (sensor_temp > TEMP_MAX);
                alert_humid <= (sensor_humid < HUMID_MIN) || (sensor_humid > HUMID_MAX);
                alert_light <= (sensor_light < LIGHT_MIN) || (sensor_light > LIGHT_MAX);

                // ============================================
                // FAULT DETECTION
                // ============================================
                // Detect stuck sensors (same value for multiple readings)
                if (ui_in == last_soil_reading && sensor_sel == 2'b00) begin
                    fault_soil_stuck <= 1;
                end else if (sensor_sel == 2'b00) begin
                    fault_soil_stuck <= 0;
                    last_soil_reading <= ui_in;
                end

                if (ui_in == last_temp_reading && sensor_sel == 2'b01) begin
                    fault_temp_stuck <= 1;
                end else if (sensor_sel == 2'b01) begin
                    fault_temp_stuck <= 0;
                    last_temp_reading <= ui_in;
                end

                if (ui_in == last_humid_reading && sensor_sel == 2'b10) begin
                    fault_humid_stuck <= 1;
                end else if (sensor_sel == 2'b10) begin
                    fault_humid_stuck <= 0;
                    last_humid_reading <= ui_in;
                end

                if (ui_in == last_light_reading && sensor_sel == 2'b11) begin
                    fault_light_stuck <= 1;
                end else if (sensor_sel == 2'b11) begin
                    fault_light_stuck <= 0;
                    last_light_reading <= ui_in;
                end

                // Detect extreme/impossible values
                fault_soil_extreme  <= (sensor_soil == 8'd0)  || (sensor_soil == 8'd255);
                fault_temp_extreme  <= (sensor_temp == 8'd0)  || (sensor_temp == 8'd255);
                fault_humid_extreme <= (sensor_humid == 8'd0) || (sensor_humid == 8'd255);
                fault_light_extreme <= (sensor_light == 8'd0) || (sensor_light == 8'd255);

                // Aggregate faults
                fault_code <= {
                    fault_light_stuck | fault_light_extreme,
                    fault_humid_stuck | fault_humid_extreme,
                    fault_temp_stuck  | fault_temp_extreme,
                    fault_soil_stuck  | fault_soil_extreme
                };

                // Aggregate alerts
                alert_code <= {alert_light, alert_humid, alert_temp, alert_soil};
                
                // Buzzer for alerts OR faults
                buzzer_active <= alert_soil | alert_temp | alert_humid | alert_light | (|fault_code);

                // Output current sensor reading
                case (sensor_sel)
                    2'b00: status_output <= sensor_soil;
                    2'b01: status_output <= sensor_temp;
                    2'b10: status_output <= sensor_humid;
                    2'b11: status_output <= sensor_light;
                endcase

            end else begin
                // ============================================
                // CAMERA MODE (Growth Detection)
                // ============================================
                
                if (vsync) begin
                    // Start of new frame - reset counters
                    green_pixel_count  <= 0;
                    yellow_pixel_count <= 0;
                    total_pixel_count  <= 0;
                    
                end else if (href) begin
                    // Valid pixel data
                    total_pixel_count <= total_pixel_count + 1;

                    // ============================================
                    // COLOR CLASSIFICATION - Pea Microgreen Biology
                    // ============================================
                    // Immature (7-10 days): Light green cotyledons
                    // Mature (10-20 days): Deep green true leaves
                    // RGB332 format: RRR GGG BB
                    
                    // Light green detection (immature): Medium G, Low R
                    // G[4:2] = 3-5 (medium green), R[7:5] < 2 (very low red)
                    if ((ui_in[4:2] >= 3'd3) && (ui_in[4:2] <= 3'd5) && (ui_in[7:5] < 3'd2)) begin
                        green_pixel_count <= green_pixel_count + 1;  // Light green = immature
                    end
                    // Deep green detection (mature): High G, Low R
                    // G[4:2] > 5 (deep green), R[7:5] < 2 (very low red)
                    else if ((ui_in[4:2] > 3'd5) && (ui_in[7:5] < 3'd2)) begin
                        yellow_pixel_count <= yellow_pixel_count + 1;  // Reuse for "deep green"
                    end
                    
                end else if (total_pixel_count > 12'd100) begin
                    // ============================================
                    // GROWTH STAGE ANALYSIS
                    // ============================================
                    // Based on deep green (mature) vs light green (immature) ratio
                    
                    total_green <= green_pixel_count + yellow_pixel_count;
                    
                    if ((green_pixel_count + yellow_pixel_count) > 12'd10) begin
                        // Simple ratio: if deep > light, mature; else immature
                        if (yellow_pixel_count > green_pixel_count) begin
                            // More deep green than light = mature (60-100%)
                            if (yellow_pixel_count > (green_pixel_count << 1)) begin
                                maturity_percent <= 8'd90;  // Deep >> Light = very mature
                            end else begin
                                maturity_percent <= 8'd70;  // Deep > Light = mature
                            end
                        end else begin
                            // More light green than deep = immature (0-40%)
                            if (green_pixel_count > (yellow_pixel_count << 1)) begin
                                maturity_percent <= 8'd20;  // Light >> Deep = very immature
                            end else begin
                                maturity_percent <= 8'd40;  // Light > Deep = somewhat immature
                            end
                        end
                    end else begin
                        maturity_percent <= 0;
                    end

                    // ============================================
                    // GROWTH STAGE CLASSIFICATION
                    // ============================================
                    // Stage 0-1: Germination (0-20% mature)
                    // Stage 2-3: Early growth (20-40% mature)
                    // Stage 4-5: Mid growth (40-60% mature)
                    // Stage 6-7: Mature/Ready (60-100% mature)
                    if (maturity_percent >= 8'd80) begin
                        growth_stage <= 3'd7;  // Fully mature (>80%)
                        growth_ready <= 1;     // HARVEST NOW!
                    end else if (maturity_percent >= 8'd60) begin
                        growth_stage <= 3'd6;  // Nearly ready (60-80%)
                        growth_ready <= 1;     // Can harvest
                    end else if (maturity_percent >= 8'd40) begin
                        growth_stage <= 3'd4;  // Mid-growth (40-60%)
                        growth_ready <= 0;     // Wait a bit more
                    end else if (maturity_percent >= 8'd20) begin
                        growth_stage <= 3'd2;  // Early growth (20-40%)
                        growth_ready <= 0;     // Too early
                    end else begin
                        growth_stage <= 3'd1;  // Germination (0-20%)
                        growth_ready <= 0;     // Way too early
                    end

                    // Buzzer for harvest ready
                    buzzer_active <= growth_ready;
                end

                // Output growth status
                status_output <= {growth_ready, growth_stage, alert_code};
            end
        end
    end

    // ============================================
    // OUTPUT ASSIGNMENTS
    // ============================================
    assign uo_out = {buzzer_active, status_output[6:0]};

    // ============================================
    // SUPPRESS UNUSED SIGNAL WARNINGS
    // ============================================
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, 
                     uio_in[4:2],              // Reserved control pins
                     green_pixel_count[11:8],  // Upper bits of pixel counters
                     yellow_pixel_count[11:8],
                     total_pixel_count[11:8],
                     total_green,              // Total green calculation
                     maturity_percent,         // Internal calculation
                     status_output[7],         // MSB reused in uo_out
                     1'b0};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule

/* verilator lint_on TIMESCALEMOD */

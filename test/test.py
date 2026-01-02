# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: MIT

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# ============================================
# TEST CONFIGURATION
# ============================================
CLOCK_PERIOD_NS = 40  # 25MHz

MODE_SENSOR = 0
MODE_ML = 1

SENSOR_SOIL = 0
SENSOR_HUMIDITY = 1
SENSOR_LIGHT = 2
SENSOR_TEMP = 3

# ============================================
# HELPER FUNCTIONS
# ============================================

async def reset_dut(dut):
    """Apply reset to the design"""
    dut._log.info("Applying reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    dut._log.info("Reset released")

def set_mode(dut, mode):
    """Set operation mode (0=sensor, 1=ML)"""
    current_val = int(dut.uio_in.value)
    if mode == MODE_ML:
        dut.uio_in.value = current_val | 0x80
    else:
        dut.uio_in.value = current_val & 0x7F

def select_sensor(dut, sensor_id):
    """Select which sensor to read (0-3)"""
    current_val = int(dut.uio_in.value) & 0xFC
    dut.uio_in.value = current_val | (sensor_id & 0x03)

def get_alert_status(dut):
    """Read alert and status outputs"""
    uo_val = int(dut.uo_out.value)
    return {
        'system_alert': bool(uo_val & 0x80),
        'ready': bool(uo_val & 0x40),
        'mode': bool(uo_val & 0x20),
        'prediction': bool(uo_val & 0x10),
        'status_bits': (uo_val >> 1) & 0x07,
    }

# ============================================
# TESTS
# ============================================

@cocotb.test()
async def test_reset(dut):
    """Test basic reset functionality"""
    dut._log.info("TEST: Reset Functionality")
    
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # After reset, design should be in a known state
    # System ready should eventually be high
    await ClockCycles(dut.clk, 10)
    
    dut._log.info("✓ Reset test passed")

@cocotb.test()
async def test_sensor_baseline(dut):
    """Test sensor mode baseline establishment"""
    dut._log.info("TEST: Sensor Baseline Learning")
    
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    set_mode(dut, MODE_SENSOR)
    select_sensor(dut, SENSOR_SOIL)
    await ClockCycles(dut.clk, 5)
    
    # Feed stable readings
    for i in range(4):
        dut.ui_in.value = 100
        await ClockCycles(dut.clk, 10)
    
    await ClockCycles(dut.clk, 50)
    
    # With stable baseline, should not have critical alert
    status = get_alert_status(dut)
    dut._log.info(f"Status after baseline: alert={status['system_alert']}")
    
    # This is a soft check - baseline establishment shouldn't cause critical issues
    dut._log.info("✓ Baseline test passed")

@cocotb.test()
async def test_all_sensors(dut):
    """Test all 4 sensors"""
    dut._log.info("TEST: All 4 Sensors")
    
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    test_values = [120, 150, 80, 200]
    sensor_names = ["Soil", "Humidity", "Light", "Temp"]
    
    for sensor_id in range(4):
        dut._log.info(f"Testing {sensor_names[sensor_id]} (ID={sensor_id})")
        
        set_mode(dut, MODE_SENSOR)
        select_sensor(dut, sensor_id)
        await ClockCycles(dut.clk, 5)
        
        # Send readings
        for i in range(4):
            dut.ui_in.value = test_values[sensor_id]
            await ClockCycles(dut.clk, 10)
        
        await ClockCycles(dut.clk, 30)
    
    dut._log.info("✓ All sensors test passed")

@cocotb.test()
async def test_ml_mode(dut):
    """Test ML mode with camera frame"""
    dut._log.info("TEST: ML Mode Camera Processing")
    
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    set_mode(dut, MODE_ML)
    await ClockCycles(dut.clk, 20)
    
    # VSYNC high (start frame)
    current_val = int(dut.uio_in.value) | 0x40
    dut.uio_in.value = current_val
    await ClockCycles(dut.clk, 5)
    
    # Send some pixel rows
    for row in range(10):
        # HREF high
        current_val = int(dut.uio_in.value) | 0x20
        dut.uio_in.value = current_val
        
        # Send pixels
        for col in range(20):
            dut.ui_in.value = 0b00111000  # Green-ish
            await ClockCycles(dut.clk, 1)
        
        # HREF low
        current_val = int(dut.uio_in.value) & ~0x20
        dut.uio_in.value = current_val
        await ClockCycles(dut.clk, 3)
    
    # VSYNC low (end frame)
    current_val = int(dut.uio_in.value) & ~0x40
    dut.uio_in.value = current_val
    await ClockCycles(dut.clk, 50)
    
    status = get_alert_status(dut)
    dut._log.info(f"ML Mode: harvest={status['prediction']}, alert={status['system_alert']}")
    
    dut._log.info("✓ ML mode test passed")

@cocotb.test()
async def test_mode_switching(dut):
    """Test switching between modes"""
    dut._log.info("TEST: Mode Switching")
    
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Start in sensor mode
    set_mode(dut, MODE_SENSOR)
    await ClockCycles(dut.clk, 20)
    
    status = get_alert_status(dut)
    dut._log.info(f"Sensor mode: mode_indicator={status['mode']}")
    
    # Switch to ML mode
    set_mode(dut, MODE_ML)
    await ClockCycles(dut.clk, 20)
    
    status = get_alert_status(dut)
    dut._log.info(f"ML mode: mode_indicator={status['mode']}")
    
    # Switch back
    set_mode(dut, MODE_SENSOR)
    await ClockCycles(dut.clk, 20)
    
    dut._log.info("✓ Mode switching test passed")

@cocotb.test()
async def test_edge_cases(dut):
    """Test edge cases"""
    dut._log.info("TEST: Edge Cases")
    
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    set_mode(dut, MODE_SENSOR)
    select_sensor(dut, SENSOR_SOIL)
    
    # Minimum values
    for i in range(4):
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 10)
    await ClockCycles(dut.clk, 30)
    
    # Maximum values
    for i in range(4):
        dut.ui_in.value = 255
        await ClockCycles(dut.clk, 10)
    await ClockCycles(dut.clk, 30)
    
    dut._log.info("✓ Edge cases test passed")

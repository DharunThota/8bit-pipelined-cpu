# ELL7282 Assignment 2: Five-Stage Pipelined Microcontroller for a Washing Machine

**Name:** Dharun Thota
**Entry No.:** 2026EET2401

## 1. Logisim version

Logisim-evolution 5.0.0.
Open `washing_pipeline.circ` with **File > Open**. No extra libraries are needed.

## 2. Contents

| File | Contents |
|---|---|
| `washing_pipeline.circ` | the complete design |
| `program.asm` | washing-machine control program (source) |
| `program.hex` | the same program as a ROM image (Logisim "v2.0 raw") |
| `isa.pdf` | instruction formats, opcode map, reserved bits, custom instruction SLTU |
| `architecture.pdf` | block diagram, pipeline registers, forwarding, stall, flush, HALT, interlock |
| `memory_map.pdf` | data addresses, peripheral registers, bit fields, timer |
| `listing.pdf` | program listing: address, hex, assembly |
| `pipeline_traces.pdf` | cycle-by-cycle traces for cases 8.1 to 8.4 and the wrong-path HALT |
| `validation.pdf` | the six validation groups: program, inputs, expected, observed, pass/fail |
| `README.md` | this file |

## 3. Circuits in `washing_pipeline.circ`

| Circuit | Description |
|---|---|
| **main** | the top-level circuit that is submitted: the whole five-stage pipelined processor, the Clock (`CLK`), input pins for RESET and the plant, and output pins for everything |
| CPU_SC | single-cycle version of the same processor, kept as a reference |
| Stage blocks | NEXT_PC, ID_STAGE, EX_STAGE, MEM_STAGE |
| Pipeline | PIPE_IFID, PIPE_IDEX, PIPE_EXMEM, PIPE_MEMWB |
| Control | HAZ (stall, flush, enables), FWD (forwarding selects) |
| PERIPH | actuator latch, DISPLAY, timer, START edge detector, safety latch |
| Library | DECODE, CTRL, REGFILE, ALU, adders, muxes, decoders, comparators |

Every flip-flop and register is a built-in Register component.

## 4. Loading a program

1. Open **main** (double-click it in the circuit list).
2. Right-click the ROM labelled **IMEM** and choose **Load Image...**
3. Select `program.hex`.

To enter a short program by hand instead, right-click IMEM, choose **Edit Contents...** and type the hex words from the listing, starting at address 00.

## 5. Clock and reset

- Every register in the design uses one global clock and triggers on the rising edge.
- In main the Clock `CLK` drives the CPU. Set a slow rate with **Simulate > Auto-Tick Frequency** (4 to 16 Hz is comfortable), then start it with **Simulate > Auto-Tick Enabled**. **Simulate > Tick Full Cycle** steps one clock at a time.
- `RESET` is an input pin. Set it to 1 and back to 0. It is asynchronous and clears the PC, HALTED, the valid bits of all four pipeline registers, and in PERIPH the actuator latch, DISPLAY, the timer, START_PEND and the safety latch TRIP. The register file and the RAM are not cleared; every program initialises what it uses.
- After HALT the CPU stops fetching; the timer and the safety logic keep running. Pulse RESET to run again.

## 6. Plant inputs and outputs

**Input pins on main**

| Pin | Meaning |
|---|---|
| `START` | 1 = start request (hold it until DOOR_LOCK turns on) |
| `MODE[1:0]` | 00 = LIGHT, 01/10/11 = HEAVY; sampled once, when START is accepted |
| `DOOR_CLOSED` | 1 = door closed |
| `WATER_LEVEL` | 8-bit unsigned level |
| `TEMP` | 8-bit reading (read-only in this design) |
| `DRUM_RPM` | 8-bit reading; the program unlocks the door only when it is 0 |

The program reads them through memory-mapped registers (see `memory_map.pdf`):

- `0xF0` IN_STATUS: START (bit 0), DOOR_CLOSED (bit 1), MODE (bits 3:2), START_PEND (bit 4), TRIP (bit 5)
- `0xF1` WATER_LEVEL, `0xF2` TEMP, `0xF3` DRUM_RPM

Change an input only while CLK is 0, so it is stable at the next rising edge.

**Outputs**

- **Actuators:** VALVE_IN, HEATER, MOTOR_EN_REQ (the command), MOTOR_EN_ACTUAL (after the door gate and TRIP), MOTOR_DIR, PUMP_OUT, DOOR_LOCK, BUZZER, DISPLAY[7:0]
- **Status:** TRIP, START_PEND, TIMER_COUNT, TIMER_MATCH, TIMER_EN
- **CPU debug:** PC, HALTED, stage valid bits and PCs, STALL, FLUSH, SEL_A, SEL_B, LOADFWD, WB_WE / WB_RD / WB_DATA, ST_WE / ST_ADDR / ST_DATA

## 7. Running the washing program by hand

Load `program.hex`. Set DOOR_CLOSED = 1, START = 0, MODE = 00, WATER_LEVEL = 0, DRUM_RPM = 0, pulse RESET and start Auto-Tick.

| You do | You should see |
|---|---|
| (wait) | DISPLAY = 0x01 (idle), all actuators 0 |
| START = 1 | START_PEND = 1, then DOOR_LOCK = 1 |
| START = 0 | after a short lock delay: DISPLAY = 0x02, VALVE_IN = 1 |
| WATER_LEVEL = 99, then 102 | VALVE_IN stays on at 99 and turns off at 102 (LIGHT target 100; HEAVY target 180) |
| (wait) | DISPLAY = 0x03; MOTOR_EN_REQ = MOTOR_EN_ACTUAL = 1, MOTOR_DIR alternates 2 times (HEAVY: 3) |
| (wait) | DISPLAY = 0x04, PUMP_OUT = 1 |
| WATER_LEVEL = 9, then 5 | pump stays on at 9, stops draining at 5 (threshold 8) |
| DRUM_RPM = 0xC8 during the spin | DISPLAY = 0x05, motor and pump on, then both off |
| DRUM_RPM = 0 | DOOR_LOCK = 0, DISPLAY = 0x0D, BUZZER = 1, HALTED = 1 |

**Safety check:** during the wash, set DOOR_CLOSED = 0. MOTOR_EN_ACTUAL drops at once and TRIP = 1 at the next clock edge. Setting DOOR_CLOSED = 1 again does not restart the motor (MOTOR_EN_REQ stays 1, MOTOR_EN_ACTUAL stays 0). RESET clears TRIP.

## 8. Validation tests

`validation.pdf` describes one test for each of the six required groups. Each test gives its program as an address / hex / assembly table, the input pins to set, the expected outputs and the observed outputs. All six pass.

To repeat a test on main:

1. Enter the program's hex words into IMEM (section 4); group 6 uses `program.hex`.
2. Set the initial inputs listed for the test and pulse RESET.
3. Run the clock (Auto-Tick, or Tick Full Cycle to step) and change the inputs as listed, only while CLK is 0.
4. Compare the output pins with the expected values. Register results appear on WB_RD and WB_DATA when WB_WE = 1; stores appear on ST_ADDR and ST_DATA when ST_WE = 1.

For group 4 (timer wraparound), keep the clock running after HALTED = 1 (a fast Auto-Tick rate helps) and watch TIMER_COUNT go 0xFF → 0x00 while TIMER_MATCH stays 1.

`pipeline_traces.pdf` uses the group 1 and group 2 programs from `validation.pdf`. Its cycle numbers count clock cycles from RESET, so they can be followed with Tick Full Cycle and the stage PC pins (IFID_PC … MEMWB_PC).

## 9. Notes

- **Data RAM (DMEM):** 7 address bits, 8 data bits, separate data buses with latched output, Asynchronous read = Yes, rising-edge trigger. With Asynchronous read = No, a load returns the previous value.
- **Built-in components used:** ROM, RAM, Register, basic gates, Splitter, Pin, Constant, Clock. Every mux, decoder, comparator, adder, incrementer and the timer are built from gates.

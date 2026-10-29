; ELL782 A2 - washing-machine control program
; ISA: opcode[15:12] I[11] Rd/RA[10:8] RB[2:0] IMM[7:0]
; Peripheral map (data addresses)
.equ IN_STATUS   0xF0   ; bit0 START, bit1 DOOR_CLOSED, bits3:2 MODE, bit4 START_PEND, bit5 TRIP
.equ WATER_LEVEL 0xF1
.equ DRUM_RPM    0xF3
.equ ACT         0xF4   ; bit0 VALVE_IN, 1 HEATER, 2 MOTOR_EN, 3 MOTOR_DIR, 4 PUMP_OUT, 5 DOOR_LOCK, 6 BUZZER
.equ DISPLAY     0xF5
.equ SYS_CTRL    0xF6   ; write bit0 = ACK_START
.equ T_LIMIT     0xF9
.equ T_CTRL      0xFA   ; write bit0 = EN, bit1 = CLR
.equ T_STATUS    0xFB   ; bit0 MATCH, bit1 EN
; RAM 0x00-0x04: parameters copied from the selected MODE
;   [0] fill target  [1] wash half-period  [2] wash cycles  [3] spin ticks  [4] drain threshold
; MODE 00 = LIGHT: 100, 10, 2, 12, 8      MODE 01/10/11 = HEAVY: 180, 16, 3, 24, 8

start:
    LDI  r0, 0
    LDI  r7, ACT
    ST   r0, [r7]        ; all actuator requests off
    LDI  r7, T_CTRL
    ST   r0, [r7]        ; timer disabled
    LDI  r7, DISPLAY
    LDI  r1, 0x01
    ST   r1, [r7]        ; DISPLAY 01 = idle
; ---- 1. wait for START and DOOR_CLOSED, snapshot MODE, lock the door
wait_start:
    LDI  r7, IN_STATUS
    LD   r3, [r7]        ; r3 = status byte (keeps the MODE snapshot)
    MOV  r1, r3
    LDI  r2, 0x03        ; START | DOOR_CLOSED
    AND  r1, r2
    SUB  r1, r2          ; 0 only if both bits are 1
    BNEZ r1, wait_start
    LDI  r7, SYS_CTRL
    LDI  r1, 0x01
    ST   r1, [r7]        ; ACK_START
    LDI  r7, ACT
    LDI  r1, 0x20
    ST   r1, [r7]        ; DOOR_LOCK on
    LDI  r7, T_LIMIT
    LDI  r1, 0x02
    ST   r1, [r7]        ; lock settle time = 2 ticks
    LDI  r7, T_CTRL
    LDI  r1, 0x03
    ST   r1, [r7]        ; timer clear + enable
settle:
    LDI  r7, T_STATUS
    LD   r1, [r7]
    LDI  r2, 0x01
    AND  r1, r2
    BEQZ r1, settle      ; wait for MATCH
    LDI  r7, IN_STATUS
    LD   r1, [r7]
    LDI  r2, 0x02        ; DOOR_CLOSED
    AND  r1, r2
    BNEZ r1, door_ok
    LDI  r0, 0           ; door opened during locking: unlock and start over
    LDI  r7, ACT
    ST   r0, [r7]
    JMP  start
door_ok:
    LDI  r2, 0x0C
    AND  r3, r2          ; r3 = MODE << 2
    BNEZ r3, heavy
light:
    LDI  r1, 100         ; fill target
    LDI  r2, 10          ; wash half-period (ticks)
    LDI  r3, 2           ; wash cycles
    LDI  r4, 12          ; spin time (ticks)
    JMP  store
heavy:
    LDI  r1, 180
    LDI  r2, 16
    LDI  r3, 3
    LDI  r4, 24
store:
    LDI  r0, 0
    ST   r1, [r0]        ; RAM[0] fill target
    ADDI r0, 1
    ST   r2, [r0]        ; RAM[1] wash half-period
    ADDI r0, 1
    ST   r3, [r0]        ; RAM[2] wash cycles
    ADDI r0, 1
    ST   r4, [r0]        ; RAM[3] spin time
    LDI  r1, 8
    ADDI r0, 1
    ST   r1, [r0]        ; RAM[4] drain threshold
; ---- 2. fill until WATER_LEVEL >= target (unsigned, overshoot-safe)
fill:
    LDI  r7, DISPLAY
    LDI  r1, 0x02
    ST   r1, [r7]        ; DISPLAY 02 = fill
    LDI  r7, ACT         ; r7 = ACT from here on
    LDI  r1, 0x21        ; lock | valve
    ST   r1, [r7]
    LDI  r0, 0
    LD   r4, [r0]        ; r4 = target
    LDI  r6, WATER_LEVEL
fill_loop:
    LD   r1, [r6]
    SLTU r1, r4          ; level < target ?
    BNEZ r1, fill_loop
    LDI  r1, 0x20
    ST   r1, [r7]        ; valve closed, lock held
; ---- 3. wash: K cycles of forward T ticks, reverse T ticks
wash:
    LDI  r6, DISPLAY
    LDI  r1, 0x03
    ST   r1, [r6]        ; DISPLAY 03 = wash
    LDI  r0, 1
    LD   r2, [r0]        ; r2 = T
    ADDI r0, 1
    LD   r3, [r0]        ; r3 = K
    LDI  r6, T_LIMIT
    ST   r2, [r6]        ; LIMIT = T
    LDI  r6, T_CTRL
    LDI  r5, T_STATUS
wash_loop:
    LDI  r1, 0x24
    ST   r1, [r7]        ; lock | motor, forward
    LDI  r1, 0x03
    ST   r1, [r6]        ; timer clear + enable
w1: LD   r1, [r5]
    LDI  r0, 0x01
    AND  r1, r0
    BEQZ r1, w1
    LDI  r1, 0x2C
    ST   r1, [r7]        ; lock | motor | reverse
    LDI  r1, 0x03
    ST   r1, [r6]        ; timer clear + enable
w2: LD   r1, [r5]
    LDI  r0, 0x01
    AND  r1, r0
    BEQZ r1, w2
    ADDI r3, 0xFF        ; K = K - 1
    BNEZ r3, wash_loop
    LDI  r1, 0x20
    ST   r1, [r7]        ; motor off, lock held
; ---- 4. drain until WATER_LEVEL <= threshold
drain:
    LDI  r6, DISPLAY
    LDI  r1, 0x04
    ST   r1, [r6]        ; DISPLAY 04 = drain
    LDI  r1, 0x30        ; lock | pump
    ST   r1, [r7]
    LDI  r0, 4
    LD   r4, [r0]        ; r4 = threshold
    LDI  r6, WATER_LEVEL
drain_loop:
    LD   r1, [r6]
    MOV  r2, r4
    SLTU r2, r1          ; threshold < level ?
    BNEZ r2, drain_loop
; ---- 5. spin for the second timer interval
spin:
    LDI  r6, DISPLAY
    LDI  r1, 0x05
    ST   r1, [r6]        ; DISPLAY 05 = spin
    LDI  r0, 3
    LD   r2, [r0]        ; r2 = spin time
    LDI  r6, T_LIMIT
    ST   r2, [r6]        ; LIMIT = spin time
    LDI  r1, 0x34        ; lock | pump | motor forward
    ST   r1, [r7]
    LDI  r6, T_CTRL
    LDI  r1, 0x03
    ST   r1, [r6]        ; timer clear + enable (rearm)
    LDI  r5, T_STATUS
s1: LD   r1, [r5]
    LDI  r0, 0x01
    AND  r1, r0
    BEQZ r1, s1
; ---- 6. stop, unlock once the drum has stopped, signal completion
done:
    LDI  r1, 0x20
    ST   r1, [r7]        ; motor and pump off, lock held
    LDI  r6, T_CTRL
    LDI  r1, 0x02
    ST   r1, [r6]        ; timer clear, disabled
    LDI  r6, DRUM_RPM
rpm_wait:
    LD   r1, [r6]
    BNEZ r1, rpm_wait    ; wait for DRUM_RPM = 0
    LDI  r1, 0x00
    ST   r1, [r7]        ; unlock
    LDI  r6, DISPLAY
    LDI  r1, 0x0D
    ST   r1, [r6]        ; DISPLAY 0D = done
    LDI  r1, 0x40
    ST   r1, [r7]        ; BUZZER
    HALT

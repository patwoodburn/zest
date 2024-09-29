const std = @import("std");
const Bus = @import("bus.zig").Bus;

const assert = std.debug.assert;

pub const CPU = struct {
    program_counter: u16,
    status: u8,
    accumulator: u8,
    stack_pointer: u16,
    register_x: u8,
    register_y: u8,

    pub fn init() CPU {
        return CPU{
            .program_counter = 0,
            .status = 0,
            .accumulator = 0,
            .stack_pointer = 0x01FF,
            .register_x = 0,
            .register_y = 0,
        };
    }

    pub fn reset(self: *CPU, bus: *Bus) void {
        bus.write(0x0000, @intFromEnum(OpCodes.INS_LDA_IM));
        bus.write(0x0001, 35);
        self.program_counter = 0;
        self.status = 0;
        self.accumulator = 0;
        self.stack_pointer = 0x01FF;
        self.register_x = 0;
        self.register_y = 0;
    }

    fn fetch(self: *CPU, cycles: *i16, bus: *Bus) u8 {
        cycles.* = cycles.* - 1;
        defer self.program_counter += 1;
        return bus.read(self.program_counter);
    }

    fn fetch_16(self: *CPU, cycles: *i16, bus: *Bus) u16 {
        var data: u16 = @as(u16, fetch(self, cycles, bus));
        data |= @as(u16, fetch(self, cycles, bus)) << 8;
        return std.mem.littleToNative(u16, data);
    }

    fn fetch_mem_adder(_: *CPU, cycles: *i16, bus: *Bus, adder: u16) u8 {
        cycles.* = cycles.* - 1;
        return bus.read(adder);
    }

    fn fetch_16_mem_adder(self: *CPU, cycles: *i16, bus: *Bus, adder: u16) u16 {
        // were reading from little so build it like little then to native
        var data: u16 = @as(u16, fetch_mem_adder(self, cycles, bus, adder)) << 8;
        data |= @as(u16, fetch_mem_adder(self, cycles, bus, adder + 1));
        return std.mem.littleToNative(u16, data);
    }

    fn write(_: *CPU, cycles: *i16, bus: *Bus, value: u8, location: u16) void {
        cycles.* = cycles.* - 1;
        bus.write(location, value);
    }

    fn write_16(cpu: *CPU, cycles: *i16, bus: *Bus, value: u16, location: u16) void {
        cpu.write(cycles, bus, @truncate(value), location);
        cpu.write(cycles, bus, @truncate(@byteSwap(value)), location + 1);
    }

    pub fn execute(self: *CPU, cycles: *i16, bus: *Bus) void {
        std.debug.print("start execution: \n", .{});
        while (cycles.* > 0) {
            std.debug.print("program counter: {x};\n", .{self.program_counter});
            std.debug.print("next op code: {x};\n", .{bus.read(self.program_counter)});
            std.debug.print("cycles remaining: {};\n", .{cycles.*});
            const instruction: OpCodes = @enumFromInt(self.fetch(cycles, bus));
            instruction.runOpCode(self, cycles, bus);
        }
        std.debug.print("end execution: \n", .{});
    }
};

fn zeropage_r_lookup(cpu: *CPU, cycles: *i16, bus: *Bus, lookup: u8) u8 {
    cycles.* = cycles.* - 1;
    return lookup +% cpu.fetch(cycles, bus);
}

fn absolute_r_lookup(cpu: *CPU, cycles: *i16, bus: *Bus, lookup: u8) u16 {
    const base_adder = cpu.fetch_16(cycles, bus); // 2 cycles
    const most_significant: u8 = @truncate(@byteSwap(base_adder));
    const combind_adder = base_adder + lookup;
    const most_significant_checker: u8 = @truncate(@byteSwap(combind_adder));
    if (most_significant_checker > most_significant) {
        cycles.* = cycles.* - 1; // 3 cycles
    }
    return combind_adder;
}

fn inderect_x_lookup(cpu: *CPU, cycles: *i16, bus: *Bus) u16 {
    const base_adder = cpu.fetch(cycles, bus); // 2nd cycels
    const lsb: u8 = base_adder +% cpu.register_x;
    cycles.* = cycles.* - 1; // 6th cycles
    return cpu.fetch_16_mem_adder(cycles, bus, @as(u16, lsb)); // 3rd 4th cycles
}

fn inderect_y_lookup(_: *CPU, _: *i16, _: *Bus) u8 {
    unreachable;
}

fn do_addition(cpu: *CPU, value_1: u8, value_2: u8) u8 {
    const result: u9 = value_1 + value_2;
    if (result > 0x0ff) {
        cpu.status |= 0b00000001;
    } else {
        cpu.status ^= 0b00000001;
    }
    return @truncate(result);
}

const OpCodes = enum(u8) {
    // lda functions
    INS_LDA_IM = 0xA9,
    INS_LDA_ZP = 0xA5,
    INS_LDA_ZPX = 0xB5,
    INS_LDA_ABS = 0xAD,
    INS_LDA_ABSX = 0xBD,
    INS_LDA_ABSY = 0xB9,
    INS_LDA_INDX = 0xA1,
    INS_LDA_INDY = 0xB1,
    // ldx functions
    INS_LDX_IM = 0xA2,
    INS_LDX_ZP = 0xA6,
    INS_LDX_ZPY = 0xB6,
    INS_LDX_ABS = 0xAE,
    INS_LDX_ABSY = 0xBE,
    // ldy functions
    // todo
    // sta functions
    INS_STA_ZP = 0x85,
    INS_STA_ZPX = 0x95,
    INS_STA_ABS = 0x8D,
    INS_STA_ABSX = 0x9D,
    INS_STA_ABSY = 0x99,
    INS_STA_INDX = 0x81,
    INS_STA_INDY = 0x91,
    // adc
    INS_ADC_IM = 0x69,
    // other
    INS_JSR = 0x20,
    INS_RTS = 0x60,
    NOP = 0xEA,

    fn runOpCode(self: OpCodes, cpu: *CPU, cycles: *i16, bus: *Bus) void {
        switch (self) {
            // lda functions
            OpCodes.INS_LDA_IM => {
                cpu.accumulator = cpu.fetch(cycles, bus);
                cpu.status = LD_status(cpu.accumulator, cpu.status);
            },
            OpCodes.INS_LDA_ZP => {
                cpu.accumulator = cpu.fetch_mem_adder(cycles, bus, cpu.fetch(cycles, bus));
                cpu.status = LD_status(cpu.accumulator, cpu.status);
            },
            OpCodes.INS_LDA_ZPX => {
                cpu.accumulator = cpu.fetch_mem_adder(cycles, bus, zeropage_r_lookup(cpu, cycles, bus, cpu.register_x));
                cpu.status = LD_status(cpu.accumulator, cpu.status);
            },
            OpCodes.INS_LDA_ABS => {
                cpu.accumulator = cpu.fetch_mem_adder(cycles, bus, cpu.fetch_16(cycles, bus));
                cpu.status = LD_status(cpu.accumulator, cpu.status);
            },
            OpCodes.INS_LDA_ABSX => {
                cpu.accumulator = cpu.fetch_mem_adder(cycles, bus, absolute_r_lookup(cpu, cycles, bus, cpu.register_x));
                cpu.status = LD_status(cpu.accumulator, cpu.status);
            },
            OpCodes.INS_LDA_ABSY => {
                cpu.accumulator = cpu.fetch_mem_adder(cycles, bus, absolute_r_lookup(cpu, cycles, bus, cpu.register_y)); // 4th cycles
                cpu.status = LD_status(cpu.accumulator, cpu.status);
            },
            OpCodes.INS_LDA_INDX => {
                cpu.accumulator = cpu.fetch_mem_adder(cycles, bus, inderect_x_lookup(cpu, cycles, bus)); // 5th
                cpu.status = LD_status(cpu.accumulator, cpu.status);
            },
            OpCodes.INS_LDA_INDY => {
                cpu.accumulator = cpu.fetch_mem_adder(cycles, bus, inderect_y_lookup(cpu, cycles, bus)); // 5th
                cpu.status = LD_status(cpu.accumulator, cpu.status);
            },
            // ldx functions
            OpCodes.INS_LDX_IM => {
                cpu.register_x = cpu.fetch(cycles, bus);
                cpu.status = LD_status(cpu.register_x, cpu.status);
            },
            OpCodes.INS_LDX_ZP => {
                cpu.register_x = cpu.fetch_mem_adder(cycles, bus, @as(u16, cpu.fetch(cycles, bus)));
                cpu.status = LD_status(cpu.register_x, cpu.status);
            },
            OpCodes.INS_LDX_ZPY => {
                cpu.register_x = cpu.fetch_mem_adder(cycles, bus, zeropage_r_lookup(cpu, cycles, bus, cpu.register_y));
                cpu.status = LD_status(cpu.register_x, cpu.status);
            },
            OpCodes.INS_LDX_ABS => {
                cpu.register_x = cpu.fetch_mem_adder(cycles, bus, cpu.fetch_16(cycles, bus));
                cpu.status = LD_status(cpu.register_x, cpu.status);
            },
            OpCodes.INS_LDX_ABSY => {
                cpu.register_x = cpu.fetch_mem_adder(cycles, bus, absolute_r_lookup(cpu, cycles, bus, cpu.register_y));
                cpu.status = LD_status(cpu.register_x, cpu.status);
            },
            //load y
            //store accumulator
            OpCodes.INS_STA_ZP => {
                cpu.write(cycles, bus, cpu.accumulator, cpu.fetch(cycles, bus));
            },
            OpCodes.INS_STA_ZPX => {
                cpu.write(cycles, bus, cpu.accumulator, zeropage_r_lookup(cpu, cycles, bus, cpu.register_x));
            },
            OpCodes.INS_STA_ABS => {
                cpu.write(cycles, bus, cpu.accumulator, cpu.fetch_16(cycles, bus));
            },
            OpCodes.INS_STA_ABSX => {
                cpu.write(cycles, bus, cpu.accumulator, absolute_r_lookup(cpu, cycles, bus, cpu.register_x));
            },
            OpCodes.INS_STA_ABSY => {
                cpu.write(cycles, bus, cpu.accumulator, absolute_r_lookup(cpu, cycles, bus, cpu.register_y));
            },
            OpCodes.INS_STA_INDX => {
                cpu.write(cycles, bus, cpu.accumulator, inderect_x_lookup(cpu, cycles, bus));
            },
            OpCodes.INS_STA_INDY => {
                cpu.write(cycles, bus, cpu.accumulator, inderect_y_lookup(cpu, cycles, bus));
            },
            // adc instructions
            OpCodes.INS_ADC_IM => {
                cpu.accumulator = do_addition(cpu, cpu.accumulator, cpu.fetch(cycles, bus));
            },
            // other instructions
            OpCodes.INS_JSR => {
                std.debug.print("ins jsr;\n", .{});
                std.debug.print("stack pointer {x}\n", .{cpu.stack_pointer});
                const new_counter = cpu.fetch_16(cycles, bus);
                cpu.write_16(cycles, bus, cpu.program_counter, cpu.stack_pointer - 1);
                cpu.stack_pointer = cpu.stack_pointer - 2;
                cpu.program_counter = new_counter;
                std.debug.print("new program counter, {x}; \n", .{cpu.program_counter});
                cycles.* = cycles.* - 1;
                std.debug.print("stack pointer {x}\n", .{cpu.stack_pointer});
            },
            OpCodes.INS_RTS => {
                std.debug.print("ins rts;\n", .{});
                std.debug.print("stack pointer {x}\n", .{cpu.stack_pointer});
                std.debug.print("program counter: {x}\n", .{cpu.program_counter});
                cpu.program_counter = cpu.fetch_16_mem_adder(cycles, bus, cpu.stack_pointer);
                cpu.stack_pointer = cpu.stack_pointer + 2;
                cycles.* = cycles.* - 1;
            },
            OpCodes.NOP => {
                cycles.* = cycles.* - 1;
            },
            // else => {
            //    unreachable;
            //},
        }
    }
};

fn LD_status(read_value: u8, current_status: u8) u8 {
    var status = current_status;
    if (read_value == 0) {
        status = current_status | 0b00000010;
    } else {
        status = current_status ^ 0b00000010;
    }
    if (read_value & 0b10000000 != 0) {
        status = current_status | 0b10000000;
    } else {
        status = current_status ^ 0b10000000;
    }
    return status;
}
// TEST BLOCK
// basic cpu functions
test "cpu fetch gets next byte bus, takes one cycle, counts program up, and does not mutate bus" {
    var memory = [5]u8{ 0x10, 0x24, 0x17, 0x21, 0x03 };
    var cpu = CPU.init();
    var cycles: i16 = 5;
    var bus = Bus.init();
    bus.recal_memory(&memory);
    try std.testing.expectEqual(cpu.program_counter, 0);
    try std.testing.expectEqual(@as(u8, 0x10), cpu.fetch(&cycles, &bus));
    try std.testing.expectEqual(cpu.program_counter, 1);
    try std.testing.expectEqual(cycles, 4);
    try std.testing.expectEqual(@as(u8, 0x24), cpu.fetch(&cycles, &bus));
    try std.testing.expectEqual(cpu.program_counter, 2);
    try std.testing.expectEqual(cycles, 3);
}

test "cpu fetch_16 gets next two byte bus, takes two cycle, counts program up, and does not mutate bus" {
    var memory = [5]u8{ 0x10, 0x24, 0x17, 0x21, 0x03 };
    var cpu = CPU.init();
    var cycles: i16 = 5;
    var bus = Bus.init();
    bus.recal_memory(&memory);
    try std.testing.expectEqual(cpu.program_counter, 0);
    try std.testing.expectEqual(@as(u16, std.mem.littleToNative(u16, 0x2410)), cpu.fetch_16(&cycles, &bus));
    try std.testing.expectEqual(cpu.program_counter, 2);
    try std.testing.expectEqual(cycles, 3);
    try std.testing.expectEqual(@as(u16, std.mem.littleToNative(u16, 0x2117)), cpu.fetch_16(&cycles, &bus));
    try std.testing.expectEqual(cpu.program_counter, 4);
    try std.testing.expectEqual(cycles, 1);
}

test "cpu fatch_mem_adder gets byte at location, does not count program up, does not mutate bus, and takes one cycle" {
    var memory = [5]u8{ 0x10, 0x24, 0x17, 0x21, 0x03 };
    var cpu = CPU.init();
    var cycles: i16 = 5;
    var bus = Bus.init();
    bus.recal_memory(&memory);
    try std.testing.expectEqual(cpu.program_counter, 0);
    try std.testing.expectEqual(@as(u8, 0x17), cpu.fetch_mem_adder(&cycles, &bus, 0x02));
    try std.testing.expectEqual(cpu.program_counter, 0);
    try std.testing.expectEqual(cycles, 4);
}

test "cpu fatch_16_mem_adder gets byte at location, does not count program up, does not mutate bus, and takes one cycle" {
    var memory = [5]u8{ 0x10, 0x24, 0x17, 0x21, 0x03 };
    var cpu = CPU.init();
    var cycles: i16 = 5;
    var bus = Bus.init();
    bus.recal_memory(&memory);
    try std.testing.expectEqual(cpu.program_counter, 0);
    try std.testing.expectEqual(@as(u16, std.mem.littleToNative(u16, 0x2103)), cpu.fetch_16_mem_adder(&cycles, &bus, 0x03));
    try std.testing.expectEqual(cpu.program_counter, 0);
    try std.testing.expectEqual(cycles, 3);
}

test "cpu write sets byte at location and uses a cycle" {
    var memory = [5]u8{ 0x10, 0x24, 0x17, 0x21, 0x03 };
    var cpu = CPU.init();
    var cycles: i16 = 5;
    var bus = Bus.init();
    bus.recal_memory(&memory);
    try std.testing.expectEqual(cpu.program_counter, 0);
    cpu.write(&cycles, &bus, 0xff, 0x03);
    try std.testing.expectEqual(0xff, bus.read(0x03));
    try std.testing.expectEqual(cycles, 4);
}

test "cpu writes to bytes to bus in little endian style" {
    var memory = [5]u8{ 0x10, 0x24, 0x17, 0x21, 0x03 };
    var cpu = CPU.init();
    var cycles: i16 = 5;
    var bus = Bus.init();
    bus.recal_memory(&memory);
    try std.testing.expectEqual(cpu.program_counter, 0);
    cpu.write_16(&cycles, &bus, 300, 0x03);
    try std.testing.expectEqual(0x2c, bus.read(0x03));
    try std.testing.expectEqual(0x01, bus.read(0x04));
    try std.testing.expectEqual(cycles, 3);
}

// op code tests
// load test
test "lda impediat pulls next bit into acumulator" {
    var memory = [5]u8{ @intFromEnum(OpCodes.INS_LDA_IM), 0x24, 0x17, 0x21, 0x03 };
    var cpu = CPU.init();
    var cycles: i16 = 2;
    var bus = Bus.init();
    bus.recal_memory(&memory);
    try std.testing.expectEqual(cpu.program_counter, 0);
    try std.testing.expectEqual(cpu.accumulator, 0);
    cpu.execute(&cycles, &bus);
    try std.testing.expectEqual(cpu.accumulator, 0x24);
    try std.testing.expectEqual(cpu.program_counter, 2);
    try std.testing.expectEqual(cycles, 0);
}

// jump test

test "jump and changes stack pointer adds current instruction to bus" {
    var memory: [0x200]u8 = undefined;
    @memset(&memory, 0);
    var cpu = CPU.init();
    var cycles: i16 = 16;
    var bus = Bus.init();
    memory[0x00] = @as(u8, @intFromEnum(OpCodes.INS_JSR));
    memory[0x01] = 0x30; // go to address 0x30
    memory[0x02] = 0x01;
    memory[0x03] = @as(u8, @intFromEnum(OpCodes.NOP));
    memory[0x04] = @as(u8, @intFromEnum(OpCodes.INS_LDA_IM));
    memory[0x05] = 0x45;
    memory[0x0130] = @as(u8, @intFromEnum(OpCodes.INS_LDA_IM));
    memory[0x0131] = 0x42;
    memory[0x0132] = @as(u8, @intFromEnum(OpCodes.INS_RTS));
    bus.recal_memory(&memory);
    cpu.execute(&cycles, &bus);
    try std.testing.expectEqual(cpu.accumulator, 0x45);
    try std.testing.expectEqual(cpu.program_counter, 0x06);
    try std.testing.expectEqual(cpu.stack_pointer, 0x01ff);
}

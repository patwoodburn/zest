const std = @import("std");
const ppu = @import("ppu.zig");

pub const Bus = struct {
    ram: [2048]u8,
    ppu: *ppu.PPU,

    pub fn init(ppu_refrence: *ppu.PPU) Bus {
        var bus = Bus{
            .ram = undefined,
            .ppu = ppu_refrence,
        };
        @memset(&bus.ram, 0);
        return bus;
    }

    pub fn read(self: *Bus, adder: u16) u8 {
        if (0x0000 <= adder and 0x1FFF >= adder) {
            return self.ram[adder & 0x07FF];
        }
        if (0x2000 <= adder and 0x3FFF >= adder) {
            std.debug.print("atepmt to access memory: {x}, full adderes used {x}\n", .{ adder & 0x1FFF, adder });
            return self.ram[adder & 0x2007];
            // write to ppu
            //return self.ram[adder & 0x0007];
        }
        std.debug.print("atepmt to access memory: {x}, full adderes used {x}\n", .{ adder & 0x1FFF, adder });
        unreachable;
    }

    pub fn write(self: *Bus, adder: u16, value: u8) void {
        if (0x0000 <= adder and 0x1FFF >= adder) {
            self.ram[adder & 0x07FF] = value;
        }
        if (0x2000 <= adder and 0x3FFF >= adder) {
            self.ram[adder & 0x2007] = value;
        }
    }

    pub fn recal_memory(self: *Bus, memory: []u8) void {
        for (memory, 0..) |adder_value, index| {
            self.ram[index & 0x07FF] = adder_value;
        }
    }
};

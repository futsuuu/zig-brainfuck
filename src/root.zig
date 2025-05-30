const std = @import("std");

pub const Instruction = union(enum) {
    increment_value: u8,
    increment_pointer: usize,
    write_value,
    read_value,
    loop_start: struct { end: usize },
    loop_end: struct { start: usize },
};

pub const Runtime = struct {
    instructions: []const Instruction,
    index: usize = 0,

    memory: [MEMORY_SIZE]u8 = [_]u8{0} ** MEMORY_SIZE,
    pointer: usize = 0,

    writer: std.io.AnyWriter,
    reader: std.io.AnyReader,

    const MEMORY_SIZE: usize = 30000;

    pub fn execute(self: *Runtime) !void {
        while (getItem(Instruction, self.instructions, self.index)) |instruction| : (self.index += 1) {
            try self.next(instruction);
        }
    }

    test execute {
        const allocator = std.testing.allocator;
        var wbuf = std.ArrayList(u8).init(allocator);
        defer wbuf.deinit();
        var rbuf = std.io.fixedBufferStream("");
        var rt = Runtime{
            .instructions = &.{
                .{ .increment_value = 1 },
                .{ .increment_pointer = 1 },
                .{ .increment_value = 255 },
            },
            .writer = wbuf.writer().any(),
            .reader = rbuf.reader().any(),
        };
        try rt.execute();
        try std.testing.expectEqual(rt.memory[0], 1);
        try std.testing.expectEqual(rt.memory[1], 255);
    }

    inline fn next(self: *Runtime, instruction: Instruction) !void {
        switch (instruction) {
            .increment_value => |n| {
                self.memory[self.pointer] +%= n;
            },
            .increment_pointer => |n| {
                self.pointer +%= n;
            },
            .write_value => {
                try self.writer.writeByte(self.memory[self.pointer]);
            },
            .read_value => {
                self.memory[self.pointer] = try self.reader.readByte();
            },
            .loop_start => |loop| {
                if (self.memory[self.pointer] == 0) self.index = loop.end;
            },
            .loop_end => |loop| {
                if (self.memory[self.pointer] != 0) self.index = loop.start;
            },
        }
    }
};

pub const ParseError = std.mem.Allocator.Error || error{InvalidSyntax};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError![]const Instruction {
    var instructions = std.ArrayList(Instruction).init(allocator);
    defer instructions.deinit();

    var loop_start_stack = std.ArrayList(usize).init(allocator);
    defer loop_start_stack.deinit();
    for (source) |char| {
        const previous = if (instructions.items.len == 0) null else &instructions.items[instructions.items.len - 1];
        switch (char) {
            '+' => b: {
                if (previous) |prev| switch (prev.*) {
                    .increment_value => |*n| {
                        n.* +%= 1;
                        break :b;
                    },
                    else => {},
                };
                try instructions.append(.{ .increment_value = 1 });
            },
            '-' => b: {
                if (previous) |prev| switch (prev.*) {
                    .increment_value => |*n| {
                        n.* -%= 1;
                        break :b;
                    },
                    else => {},
                };
                try instructions.append(.{ .increment_value = std.math.maxInt(u8) });
            },
            '>' => b: {
                if (previous) |prev| switch (prev.*) {
                    .increment_pointer => |*n| {
                        n.* +%= 1;
                        break :b;
                    },
                    else => {},
                };
                try instructions.append(.{ .increment_pointer = 1 });
            },
            '<' => b: {
                if (previous) |prev| switch (prev.*) {
                    .increment_pointer => |*n| {
                        n.* -%= 1;
                        break :b;
                    },
                    else => {},
                };
                try instructions.append(.{ .increment_pointer = std.math.maxInt(usize) });
            },
            '.' => {
                try instructions.append(.write_value);
            },
            ',' => {
                try instructions.append(.read_value);
            },
            '[' => {
                try loop_start_stack.append(instructions.items.len);
                try instructions.append(.{ .loop_start = .{ .end = 0 } });
            },
            ']' => {
                const start = loop_start_stack.pop() orelse {
                    std.debug.print("too many ']'\n", .{});
                    return error.InvalidSyntax;
                };
                const end = instructions.items.len;
                instructions.items[start].loop_start.end = end;
                try instructions.append(.{ .loop_end = .{ .start = start } });
            },
            else => {},
        }
    }
    if (loop_start_stack.items.len != 0) {
        std.debug.print("too many '['\n", .{});
        return error.InvalidSyntax;
    }

    return try instructions.toOwnedSlice();
}

test parse {
    const allocator = std.testing.allocator;

    const expected: []const Instruction = &.{
        .{ .increment_value = 2 },
        .{ .increment_pointer = 2 },
        .{ .loop_start = .{ .end = 5 } },
        .write_value,
        .read_value,
        .{ .loop_end = .{ .start = 2 } },
        .{ .increment_value = 255 },
    };
    const actual = try parse(allocator, "++><<>>>[.,]++---");
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(Instruction, expected, actual);
}

inline fn getItem(T: type, slice: []const T, index: usize) ?T {
    return if (index < slice.len) slice[index] else null;
}

test {
    std.testing.refAllDeclsRecursive(@This());
}

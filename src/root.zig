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
    index: usize,

    memory: std.ArrayList(u8),
    pointer: usize,

    writer: std.io.AnyWriter,
    reader: std.io.AnyReader,

    pub fn init(
        allocator: std.mem.Allocator,
        instructions: []const Instruction,
        writer: std.io.AnyWriter,
        reader: std.io.AnyReader,
    ) Runtime {
        return .{
            .instructions = instructions,
            .index = 0,
            .memory = .init(allocator),
            .pointer = 0,
            .writer = writer,
            .reader = reader,
        };
    }

    pub fn deinit(self: Runtime) void {
        self.memory.deinit();
    }

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
        var rt = Runtime.init(
            allocator,
            &.{
                .{ .increment_value = 1 },
                .{ .increment_pointer = 1 },
                .{ .increment_value = 255 },
            },
            wbuf.writer().any(),
            rbuf.reader().any(),
        );
        defer rt.deinit();
        try rt.execute();
        try std.testing.expectEqual(rt.memory.items[0], 1);
        try std.testing.expectEqual(rt.memory.items[1], 255);
    }

    inline fn next(self: *Runtime, instruction: Instruction) !void {
        switch (instruction) {
            .increment_value => |n| {
                try self.extendMemory();
                self.memory.items[self.pointer] +%= n;
            },
            .increment_pointer => |n| {
                self.pointer +%= n;
            },
            .write_value => {
                try self.extendMemory();
                try self.writer.writeByte(self.memory.items[self.pointer]);
            },
            .read_value => {
                try self.extendMemory();
                self.memory.items[self.pointer] = try self.reader.readByte();
            },
            .loop_start => |args| {
                try self.extendMemory();
                if (self.memory.items[self.pointer] == 0) self.index = args.end;
            },
            .loop_end => |args| {
                try self.extendMemory();
                if (self.memory.items[self.pointer] != 0) self.index = args.start;
            },
        }
    }

    inline fn extendMemory(self: *Runtime) !void {
        if (self.memory.items.len <= self.pointer) {
            try self.memory.appendNTimes(0, self.pointer + 1 - self.memory.items.len);
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ![]const Instruction {
    var instructions = std.ArrayList(Instruction).init(allocator);
    defer instructions.deinit();

    var loop_start_stack = std.ArrayList(usize).init(allocator);
    defer loop_start_stack.deinit();
    for (source) |char| {
        const previous = if (instructions.items.len == 0) null else &instructions.items[instructions.items.len - 1];
        switch (char) {
            '+' => {
                if (previous) |prev| switch (prev.*) {
                    .increment_value => |*n| n.* +%= 1,
                    else => try instructions.append(.{ .increment_value = 1 }),
                } else try instructions.append(.{ .increment_value = 1 });
            },
            '-' => {
                if (previous) |prev| switch (prev.*) {
                    .increment_value => |*n| n.* -%= 1,
                    else => try instructions.append(.{ .increment_value = std.math.maxInt(u8) }),
                } else try instructions.append(.{ .increment_value = std.math.maxInt(u8) });
            },
            '>' => {
                if (previous) |prev| switch (prev.*) {
                    .increment_pointer => |*n| n.* +%= 1,
                    else => try instructions.append(.{ .increment_pointer = 1 }),
                } else try instructions.append(.{ .increment_pointer = 1 });
            },
            '<' => {
                if (previous) |prev| switch (prev.*) {
                    .increment_pointer => |*n| n.* -%= 1,
                    else => try instructions.append(.{ .increment_pointer = std.math.maxInt(usize) }),
                } else try instructions.append(.{ .increment_pointer = std.math.maxInt(usize) });
            },
            '.' => try instructions.append(.write_value),
            ',' => try instructions.append(.read_value),
            '[' => {
                try loop_start_stack.append(instructions.items.len);
                try instructions.append(.{ .loop_start = .{ .end = 0 } });
            },
            ']' => {
                const start = loop_start_stack.pop().?;
                switch (instructions.items[start]) {
                    .loop_start => |*args| args.end = instructions.items.len,
                    else => unreachable,
                }
                try instructions.append(.{ .loop_end = .{ .start = start } });
            },
            else => {},
        }
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

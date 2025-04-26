const std = @import("std");

const brainfuck = @import("brainfuck");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const input = args.next().?;

    const file = try std.fs.cwd().openFileZ(input, .{});
    defer file.close();
    const source = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);
    const instructions = try brainfuck.parse(allocator, source);
    defer allocator.free(instructions);

    var runtime = brainfuck.Runtime.new(
        instructions,
        std.io.getStdOut().writer().any(),
        std.io.getStdIn().reader().any(),
    );

    try runtime.execute();
}

test {
    std.testing.refAllDeclsRecursive(@This());
}

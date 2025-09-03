const std = @import("std");
const builtin = @import("builtin");
const nm = @import("nanomodbus").nanomodbus;

const RWptrs = struct {
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
};

fn transport_read(buf: [*c]u8, count: u16, byte_timeout_ms: i32, arg: ?*anyopaque) callconv(.c) i32 {
    const rw: *const RWptrs = @ptrCast(@alignCast(arg));
    const reader = rw.reader;
    const dest = buf[0..count];
    std.debug.print("To read {}...", .{count});
    if (byte_timeout_ms == 0) {
        const read_cnt = @min(reader.bufferedLen(), count);
        reader.readSliceAll(dest[0..read_cnt]) catch {
            std.debug.print("Read Error\n", .{});
            return -1;
        };
        std.debug.print(" Read with no timeout OK, read count: {}, data: {any}\n", .{ read_cnt, dest[0..read_cnt] });
        return @intCast(read_cnt);
    }
    reader.readSliceAll(dest) catch {
        std.debug.print(" Read Error\n", .{});
        return -1;
    };
    std.debug.print(" Read OK, data: {any}\n", .{dest});
    return count;
}

fn writeAllAndFlush(writer: *std.Io.Writer, data: []const u8) !void {
    try writer.writeAll(data);
    try writer.flush();
}

fn transport_write(buf: [*c]const u8, count: u16, byte_timeout_ms: i32, arg: ?*anyopaque) callconv(.c) i32 {
    _ = byte_timeout_ms;
    const rw: *RWptrs = @ptrCast(@alignCast(arg));
    const writer = rw.writer;
    const data = buf[0..count];
    std.debug.print("Write: cnt: {}, data: {any}\n", .{ count, data });
    writeAllAndFlush(writer, data) catch |err| {
        std.debug.print("Write Error {}\n", .{err});
        return -1;
    };
    return count;
}

const RegTypes = enum {
    hreg,
    ireg,
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args_iterator = try std.process.argsWithAllocator(allocator);
    defer args_iterator.deinit();
    _ = args_iterator.skip();

    const ip = args_iterator.next() orelse return error.NoIP;
    const reg_type = if (args_iterator.next()) |r| std.meta.stringToEnum(RegTypes, r) orelse return error.InvalidRegType else return error.NoRegType;
    const reg = if (args_iterator.next()) |r| try std.fmt.parseInt(u16, r, 0) else return error.NoReg;
    const cnt = if (args_iterator.next()) |c| try std.fmt.parseInt(u16, c, 0) else return error.NoCnt;

    const host = try std.net.Address.parseIp4(ip, 502);
    var stream = try std.net.tcpConnectToAddress(host);
    defer stream.close();

    var stream_reader_buffer: [1024]u8 = undefined;
    var stream_reader = stream.reader(&stream_reader_buffer);
    const reader = stream_reader.interface();

    var stream_writer_buffer: [1024]u8 = undefined;
    var stream_writer = stream.writer(&stream_writer_buffer);
    const writer = &stream_writer.interface;

    const rw: RWptrs = .{
        .reader = reader,
        .writer = writer,
    };

    std.debug.print("Connected\n", .{});

    var platform_conf: nm.nmbs_platform_conf = undefined;
    nm.nmbs_platform_conf_create(&platform_conf);
    platform_conf.transport = nm.NMBS_TRANSPORT_TCP;
    platform_conf.read = transport_read;
    platform_conf.write = transport_write;
    platform_conf.arg = @constCast(&rw);

    var nmbs: nm.nmbs_t = undefined;
    const create_err = nm.nmbs_client_create(&nmbs, &platform_conf);
    if (create_err != nm.NMBS_ERROR_NONE) {
        std.debug.print("NMBS Create error: {s}\n", .{nm.nmbs_strerror(create_err)});
        return error.NMBSError;
    }

    std.debug.print("NMBS Created\n", .{});

    nm.nmbs_set_read_timeout(&nmbs, 1000);

    std.debug.print("Reading: reg_type:{t} reg:{} cnt:{}\n", .{ reg_type, reg, cnt });

    const read_buffer = try allocator.alloc(u16, cnt);
    defer allocator.free(read_buffer);
    const read_err = switch (reg_type) {
        .ireg => nm.nmbs_read_input_registers(&nmbs, reg, cnt, read_buffer.ptr),
        .hreg => nm.nmbs_read_holding_registers(&nmbs, reg, cnt, read_buffer.ptr),
    };
    if (read_err != nm.NMBS_ERROR_NONE) {
        std.debug.print("NMBS Read error: {s}\n", .{nm.nmbs_strerror(read_err)});
        return error.NMBSError;
    }

    std.debug.print("Read: {any}\n", .{read_buffer});
}

const std = @import("std");
const nm_lib = @import("nanomodbus");
const nm = nm_lib.c;
const nm_check_error = nm_lib.nm_check_error;

const RWptrs = struct {
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
};

fn transport_read(buf: [*c]u8, count: u16, byte_timeout_ms: i32, arg: ?*anyopaque) callconv(.c) i32 {
    const rw: *const RWptrs = @ptrCast(@alignCast(arg));
    const reader = rw.reader;
    const dest = buf[0..count];
    std.log.debug("To read {}...", .{count});
    if (byte_timeout_ms == 0) {
        const read_cnt = @min(reader.bufferedLen(), count);
        reader.readSliceAll(dest[0..read_cnt]) catch {
            std.log.debug("Read Error", .{});
            return -1;
        };
        std.log.debug(" Read with no timeout OK, read count: {}, data: {any}", .{ read_cnt, dest[0..read_cnt] });
        return @intCast(read_cnt);
    }
    reader.readSliceAll(dest) catch {
        std.log.debug(" Read Error", .{});
        return -1;
    };
    std.log.debug(" Read OK, data: {any}", .{dest});
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
    std.log.debug("Write: cnt: {}, data: {any}", .{ count, data });
    writeAllAndFlush(writer, data) catch |err| {
        std.log.debug("Write Error {}", .{err});
        return -1;
    };
    return count;
}

// clear reader buffer
fn transport_flush(_: [*c]nm.nmbs_t, arg: ?*anyopaque) callconv(.c) void {
    std.log.debug("flush reader", .{});
    const rw: *RWptrs = @ptrCast(@alignCast(arg));
    rw.reader.tossBuffered();
}

const RegTypes = enum {
    hreg,
    ireg,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args_iterator = try init.minimal.args.iterateAllocator(allocator);
    defer args_iterator.deinit();
    _ = args_iterator.skip();

    const hostname = args_iterator.next() orelse return error.NoHostName;
    const reg_type = if (args_iterator.next()) |r| std.meta.stringToEnum(RegTypes, r) orelse return error.InvalidRegType else return error.NoRegType;
    const reg = if (args_iterator.next()) |r| try std.fmt.parseInt(u16, r, 0) else return error.NoReg;
    const cnt = if (args_iterator.next()) |c| try std.fmt.parseInt(u16, c, 0) else return error.NoCnt;

    const host: std.Io.net.HostName = try .init(hostname);

    var stream = try host.connect(io, 502, .{ .mode = .stream });
    defer stream.close(io);

    var stream_reader_buffer: [1024]u8 = undefined;
    var stream_reader = stream.reader(io, &stream_reader_buffer);
    const reader = &stream_reader.interface;

    var stream_writer_buffer: [1024]u8 = undefined;
    var stream_writer = stream.writer(io, &stream_writer_buffer);
    const writer = &stream_writer.interface;

    const rw: RWptrs = .{
        .reader = reader,
        .writer = writer,
    };

    std.log.info("Connected", .{});

    var platform_conf: nm.nmbs_platform_conf = undefined;
    nm.nmbs_platform_conf_create(&platform_conf);
    platform_conf.transport = nm.NMBS_TRANSPORT_TCP;
    platform_conf.read = transport_read;
    platform_conf.write = transport_write;
    platform_conf.flush = transport_flush;
    platform_conf.arg = @constCast(&rw);

    var nmbs: nm.nmbs_t = undefined;
    nm_check_error(nm.nmbs_client_create(&nmbs, &platform_conf)) catch |err| {
        std.log.err("NMBS Create error: {t}", .{err});
        return err;
    };

    std.log.info("NMBS Created", .{});

    nm.nmbs_set_read_timeout(&nmbs, 1000);

    std.log.info("Reading: reg_type:{t} reg:{} cnt:{}", .{ reg_type, reg, cnt });

    const read_buffer = try allocator.alloc(u16, cnt);
    defer allocator.free(read_buffer);

    while (true) {
        nm_check_error(switch (reg_type) {
            .ireg => nm.nmbs_read_input_registers(&nmbs, reg, cnt, read_buffer.ptr),
            .hreg => nm.nmbs_read_holding_registers(&nmbs, reg, cnt, read_buffer.ptr),
        }) catch |err| {
            std.log.err("NMBS Read error: {t}", .{err});
            return err;
        };

        std.log.info("Read: {any}", .{read_buffer});
        try io.sleep(.fromSeconds(5), .boot);
    }
}

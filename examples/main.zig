const std = @import("std");
const builtin = @import("builtin");
const nm = @import("nanomodbus");

fn transport_read(buf: [*c]u8, count: u16, timeout_ms: i32, arg: ?*anyopaque) callconv(.C) c_int {
    if (timeout_ms == 0) return 0;
    const stream: *std.net.Stream = @ptrCast(@alignCast(arg));
    // std.debug.print("To read {}\n", .{count});
    const read_count = stream.read(buf[0..count]) catch {
        // std.debug.print("Read Error\n", .{});
        return -1;
    };
    // std.debug.print("Read OK, count: {}, data: {any}\n", .{ read_count, buf[0..read_count] });
    return @intCast(read_count);
}

fn transport_write(buf: [*c]const u8, count: u16, timeout_ms: i32, arg: ?*anyopaque) callconv(.C) c_int {
    _ = timeout_ms;
    const stream: *std.net.Stream = @ptrCast(@alignCast(arg));
    // std.debug.print("Write: {any}\n", .{buf[0..count]});
    stream.writeAll(buf[0..count]) catch {
        // std.debug.print("Write Error\n", .{});
        return -1;
    };
    // std.debug.print("Write OK\n", .{});
    return count;
}

pub fn main() !void {
    const host = try std.net.Address.parseIp4("192.168.101.2", 502);
    var stream = try std.net.tcpConnectToAddress(host);
    defer stream.close();

    std.debug.print("Connected\n", .{});

    var platform_conf: nm.nmbs_platform_conf = undefined;
    nm.nmbs_platform_conf_create(&platform_conf);
    platform_conf.transport = nm.NMBS_TRANSPORT_TCP;
    platform_conf.read = transport_read;
    platform_conf.write = transport_write;
    platform_conf.arg = &stream;

    var nmbs: nm.nmbs_t = undefined;
    const create_err = nm.nmbs_client_create(&nmbs, &platform_conf);
    if (create_err != nm.NMBS_ERROR_NONE) {
        std.debug.print("NMBS Create error: {s}\n", .{nm.nmbs_strerror(create_err)});
        return error.NMBSError;
    }

    std.debug.print("NMBS Created\n", .{});

    // nm.nmbs_set_read_timeout(&nmbs, 1000);

    var read_buff: [60]u16 = undefined;
    const read_err = nm.nmbs_read_holding_registers(&nmbs, 0, read_buff.len, &read_buff);
    if (read_err != nm.NMBS_ERROR_NONE) {
        std.debug.print("NMBS Read error: {s}\n", .{nm.nmbs_strerror(read_err)});
        return error.NMBSError;
    }

    std.debug.print("Read: {any}\n", .{read_buff});

    const read_decode = std.mem.bytesAsSlice(i32, std.mem.sliceAsBytes(read_buff[0..(read_buff.len - 8)]));
    std.debug.print("Read: {any}\n", .{read_decode});

    const serial = std.mem.sliceAsBytes(read_buff[(read_buff.len - 8)..]);
    std.debug.print("Serial: {s}\n", .{serial});
}

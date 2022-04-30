const std = @import("std");
const net = std.net;
const io = std.io;
const fmt = std.fmt;
const time = std.time;
const thread = std.Thread;
const mem = std.mem;
const process = std.process;
const exit = std.os.exit;
const print = std.debug.print;

const err_prefix = "[-] error :";
const ok_prefix = "[+] server :";

/// show the program usage
pub fn usage(arg: [*:0]u8) void {
    print(
        \\ Usage : {s} [ip] [port]
        \\
    , .{arg});
}

/// read until conn EOF
pub fn readUntilEof(conn: net.Stream) void {
    var buff: [1024]u8 = undefined;
    var n_bytes: usize = 1;
    while (n_bytes != 0) {
        const line = conn.reader().readUntilDelimiterOrEof(&buff, '\n') catch {
            print("{s} couldn't read from conn...\n", .{err_prefix});
            exit(0);
        };
        if (line) |data| {
            print("{s} {s}", .{ ok_prefix, buff[0 .. data.len + 1] });
        } else {
            print("{s} disconnected...\n", .{ok_prefix});
            exit(0);
        }
    }
}

/// reading from stdin and sending to conn
/// until the first char sent in newline
pub fn writeUntilSTOP(conn: net.Stream) void {
    const stdin = io.getStdIn().reader();
    var buff: [1024]u8 = undefined;
    while (buff[0] != '\n') {
        const data = stdin.readUntilDelimiter(&buff, '\n') catch {
            print("{s} couldn't read from stdin..\n", .{err_prefix});
            continue;
        };
        _ = conn.writer().writeAll(buff[0 .. data.len + 1]) catch {
            print("{s} couldn't send data to conn..\n", .{err_prefix});
            continue;
        };
    }
    print("{s} closing connection\n", .{ok_prefix});
    exit(0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try process.argsAlloc(allocator);
    if (args.len != 3) {
        usage(args[0]);
        process.argsFree(allocator, args);
        return;
    }
    // convert arguments to ip:port
    const ip: []const u8 = mem.span(args[1]);
    const port: u16 = try fmt.parseUnsigned(u16, std.mem.span(args[2]), 10);
    const addr = try net.Address.parseIp(ip, port);
    // free the arguments since we don't need them anymore => addr contains the address
    process.argsFree(allocator, args);
    // connect to server
    const server = net.tcpConnectToAddress(addr) catch {
        print("{s} couldn't connect to {}\n", .{ err_prefix, addr });
        return;
    };
    defer server.close();
    print("{s} listening on {}\n", .{ ok_prefix, addr });
    // thread listening for messages
    const read = thread.spawn(.{}, readUntilEof, .{server}) catch {
        print("{s} couldn't start read thread..\n", .{err_prefix});
        return;
    };
    // thread sending messages
    const write = thread.spawn(.{}, writeUntilSTOP, .{server}) catch {
        print("{s} couldn't start write thread..\n", .{err_prefix});
        return;
    };
    // wait for threads to finish
    write.join();
    read.join();
}

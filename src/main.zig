const std = @import("std");
const net = std.net;
const io = std.io;
const fmt = std.fmt;
const thread = std.Thread;
const mem = std.mem;
const process = std.process;
const print = std.debug.print;

/// prefix for OK and ERROR
const err_prefix = "[-] error :";
const ok_prefix = "[+] server :";

/// struct allowing to get conn
/// either from Server or by connecting as Client
const ConnSetup = struct {
    addr: net.Address,
    serv: net.StreamServer,
    isListener: bool,

    /// init the struct
    pub fn init() ConnSetup {
        return ConnSetup{ .addr = undefined, .serv = undefined, .isListener = false };
    }

    /// connect to address or accept client
    /// and return the conn Stream
    pub fn getConn(self: *ConnSetup) !net.Stream {
        if (self.isListener) {
            self.serv = net.StreamServer.init(.{ .reuse_address = true });
            try self.serv.listen(self.addr);
            print("{s} Listening on {}\n", .{ ok_prefix, self.addr });
            const client = try self.serv.accept();
            return client.stream;
        }
        return try net.tcpConnectToAddress(self.addr);
    }

    /// deinit the server if it's set
    pub fn deinit(self: *ConnSetup) void {
        if (!self.isListener) {
            return;
        }
        self.serv.deinit();
    }
};

/// show the program usage
pub fn usage(arg: [*:0]const u8) void {
    print(
        \\ Usage : {s} [OPTION] [ip] [port]
        \\
        \\ OPTION:
        \\   -h           show this help
        \\   -l           to start as server
        \\
    , .{arg});
}

/// reading/writing data until '\n'
pub fn getAll(reader: anytype, writer: anytype, buff: []u8) void {
    var isAgain: bool = true;
    while (isAgain) {
        // read from reader
        const data = reader.readUntilDelimiter(buff, '\n') catch |e| switch (e) {
            // if error : write and read again until reaching '\n'
            error.StreamTooLong => {
                writer.writeAll(buff) catch {
                    print("{s} error when sending data\n", .{err_prefix});
                    return;
                };
                continue;
            },
            error.EndOfStream => process.exit(0), // if conn closed
            else => process.exit(6),
        };
        // if no error then write and break using isAgain
        isAgain = false;
        writer.writeAll(buff[0 .. data.len + 1]) catch {
            print("{s} error when sending data\n", .{err_prefix});
            return;
        };
    }
}

/// read from conn
pub fn readUntilEof(conn: net.Stream) !void {
    const stdout = io.getStdOut();
    const reader = conn.reader();
    var buff: [10]u8 = undefined;
    while (true) {
        getAll(reader, stdout.writer(), &buff);
    }
}

/// reading from stdin and sending to conn
pub fn writeUntilSTOP(conn: net.Stream) !void {
    const stdin = io.getStdIn();
    var buff: [10]u8 = undefined;
    while (true) {
        getAll(stdin.reader(), conn.writer(), &buff);
    }
}

/// handle the connection for read & write
pub fn handle(conn: net.Stream) !void {
    // thread listening for messages
    const read = thread.spawn(.{}, readUntilEof, .{conn}) catch {
        print("{s} couldn't start read thread..\n", .{err_prefix});
        return;
    };

    // thread sending messages
    const write = thread.spawn(.{}, writeUntilSTOP, .{conn}) catch {
        print("{s} couldn't start write thread..\n", .{err_prefix});
        return;
    };

    // wait for threads to finish
    write.join();
    read.join();
}

/// convert argv[1] & argv[2] to address
pub fn getAddress(argv1: []const u8, argv2: []const u8) !net.Address {
    const ip: []const u8 = mem.span(argv1);
    const port: u16 = try fmt.parseUnsigned(u16, std.mem.span(argv2), 10);
    const addr = try net.Address.parseIp(ip, port);
    return addr;
}

/// check if there are enough
/// and return true if "-l" is set
pub fn checkArgs(args: [][:0]const u8) error{WrongNumberOfArguments}!bool {
    if (args.len < 3 or args.len > 4) {
        return error.WrongNumberOfArguments;
    }
    if (mem.eql(u8, args[1], "-h")) {
        usage(args[0]);
        process.exit(0);
    }
    return mem.eql(u8, args[1], "-l");
}

pub fn main() void {
    // init the allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // get program arguments
    const args = process.argsAlloc(allocator) catch {
        print("{s} couldn't get program arguments\n", .{err_prefix});
        process.exit(1);
    };
    defer process.argsFree(allocator, args);

    // init struct
    var conn_setup = ConnSetup.init();

    // check if there are enough arguments
    conn_setup.isListener = checkArgs(args) catch {
        usage(args[0]);
        process.exit(2);
    };

    // convert arguments to ip:port
    conn_setup.addr = switch (conn_setup.isListener) {
        true => blk: {
            break :blk getAddress(args[2], args[3]) catch {
                print("{s} bad format for address\n", .{err_prefix});
                process.exit(3);
            };
        },
        false => blk: {
            break :blk getAddress(args[1], args[2]) catch {
                print("{s} bad format for address\n", .{err_prefix});
                process.exit(3);
            };
        },
    };

    // get conn from either server or client
    const conn: net.Stream = conn_setup.getConn() catch {
        print("{s} couldn't connect\n", .{err_prefix});
        process.exit(4);
    };
    defer conn_setup.deinit();
    defer conn.close();

    // handle the connection
    handle(conn) catch {
        print("{s} issue when handling the connection\n", .{err_prefix});
        process.exit(5);
    };
}

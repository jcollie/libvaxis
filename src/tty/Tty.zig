const std = @import("std");
const os = std.os;

const log = std.log.scoped(.tty);

const Tty = @This();

/// the original state of the terminal, prior to calling makeRaw
termios: os.termios,

/// The file descriptor we are using for I/O
fd: os.fd_t,

/// the write end of a pipe to signal the tty should exit it's run loop
quit_fd: ?os.fd_t = null,

/// initializes a Tty instance by opening /dev/tty and "making it raw"
pub fn init() !Tty {
    // Open our tty
    const fd = try os.open("/dev/tty", os.system.O.RDWR, 0);

    // Set the termios of the tty
    const termios = try makeRaw(fd);

    return Tty{
        .fd = fd,
        .termios = termios,
    };
}

/// release resources associated with the Tty return it to it's original state
pub fn deinit(self: *Tty) void {
    os.tcsetattr(self.fd, .FLUSH, self.termios) catch |err| {
        log.err("couldn't restore terminal: {}", .{err});
    };
    os.close(self.fd);
}

/// stops the run loop
pub fn stop(self: *Tty) void {
    if (self.quit_fd) |fd| {
        _ = std.os.write(fd, "q") catch {};
    }
}

/// read input from the tty
pub fn run(self: *Tty, comptime T: type, comptime _: fn (ev: T) void) !void {
    // create a pipe so we can signal to exit the run loop
    const pipe = try os.pipe();
    defer os.close(pipe[0]);
    defer os.close(pipe[1]);

    self.quit_fd = pipe[1];

    var parser: Parser = .{};

    var buf: [1024]u8 = undefined;
    var pollfds: [2]std.os.pollfd = .{
        .{ .fd = self.fd, .events = std.os.POLL.IN, .revents = undefined },
        .{ .fd = pipe[0], .events = std.os.POLL.IN, .revents = undefined },
    };
    while (true) {
        _ = try std.os.poll(&pollfds, -1);
        if (pollfds[1].revents & std.os.POLL.IN != 0) {
            log.info("quitting read thread", .{});
            return;
        }

        const n = try os.read(self.fd, &buf);
        parser.parse(self, buf[0..n]);
    }
}

/// makeRaw enters the raw state for the terminal.
pub fn makeRaw(fd: os.fd_t) !os.termios {
    const state = try os.tcgetattr(fd);
    var raw = state;
    // see termios(3)
    raw.iflag &= ~@as(
        os.tcflag_t,
        os.system.IGNBRK |
            os.system.BRKINT |
            os.system.PARMRK |
            os.system.ISTRIP |
            os.system.INLCR |
            os.system.IGNCR |
            os.system.ICRNL |
            os.system.IXON,
    );
    raw.oflag &= ~@as(os.tcflag_t, os.system.OPOST);
    raw.lflag &= ~@as(
        os.tcflag_t,
        os.system.ECHO |
            os.system.ECHONL |
            os.system.ICANON |
            os.system.ISIG |
            os.system.IEXTEN,
    );
    raw.cflag &= ~@as(
        os.tcflag_t,
        os.system.CSIZE |
            os.system.PARENB,
    );
    raw.cflag |= @as(
        os.tcflag_t,
        os.system.CS8,
    );
    raw.cc[os.system.V.MIN] = 1;
    raw.cc[os.system.V.TIME] = 0;
    try os.tcsetattr(fd, .FLUSH, raw);
    return state;
}

/// parses vt input. Retains some state so we need an object for it
const Parser = struct {
    const log = std.log.scoped(.parser);

    // the state of the parser
    const State = enum {
        ground,
        escape,
        csi,
        osc,
        dcs,
        sos,
        pm,
        apc,
        ss2,
        ss3,
    };

    state: State = .ground,

    fn parse(self: *Parser, tty: *Tty, input: []u8) void {
        _ = tty; // autofix
        var i: usize = 0;
        const start: usize = 0;
        _ = start; // autofix
        while (i < input.len) : (i += 1) {
            const b = input[i];
            switch (self.state) {
                .ground => Parser.log.err("0x{x}\r", .{b}),
                else => {},
            }
        }
    }
};

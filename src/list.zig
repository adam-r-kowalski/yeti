const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const panic = std.debug.panic;
const assert = std.debug.assert;

pub const Config = struct {
    initial_capacity: u64 = 32,
    grown_factor: u64 = 2,
};

pub fn List(comptime T: type, comptime config: Config) type {
    assert(config.grown_factor > 1);

    return struct {
        items: []T,
        len: u64,
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .items = &.{},
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn fromSlice(allocator: Allocator, data: []const T) !Self {
            const items = try allocator.dupe(T, data);
            return Self{
                .items = items,
                .len = data.len,
                .allocator = allocator,
            };
        }

        pub fn withCapacity(allocator: Allocator, capacity: u64) !Self {
            const items = try allocator.alloc(T, capacity);
            return Self{
                .items = items,
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn append(self: *Self, value: T) !void {
            if (self.items.len == self.len) {
                const capacity = std.math.max(
                    self.len * config.grown_factor,
                    config.initial_capacity,
                );
                const items = try self.allocator.alloc(T, capacity);
                std.mem.copy(T, items, self.items);
                self.allocator.free(self.items);
                self.items = items;
            }
            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn appendAssumeCapacity(self: *Self, value: T) void {
            assert(self.len < self.items.len);
            self.items[self.len] = value;
            self.len += 1;
        }

        pub fn appendSlice(self: *Self, value: []const T) !void {
            const needed_length = self.len + value.len;
            if (self.items.len < needed_length) {
                var capacity = std.math.max(
                    self.len * config.grown_factor,
                    config.initial_capacity,
                );
                while (capacity < needed_length) {
                    capacity *= config.grown_factor;
                }
                const items = try self.allocator.alloc(T, capacity);
                std.mem.copy(T, items, self.items);
                self.allocator.free(self.items);
                self.items = items;
            }
            var i: u64 = 0;
            while (i < value.len) : (i += 1) {
                self.items[self.len + i] = value[i];
            }
            self.len += value.len;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn slice(self: Self) []const T {
            return self.items[0..self.len];
        }

        pub fn mutSlice(self: Self) []T {
            return self.items[0..self.len];
        }

        pub fn last(self: Self) T {
            assert(self.len > 0);
            return self.items[self.len - 1];
        }
    };
}

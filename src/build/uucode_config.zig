const std = @import("std");
const assert = std.debug.assert;
const config = @import("config.zig");

fn buildWidth(
    comptime InputRow: type,
    comptime Row: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    inputs: config.MultiSlice(InputRow),
    rows: *config.MultiSlice(Row),
    backing: anytype,
    tracking: anytype,
) !void {
    _ = allocator;
    _ = io;
    _ = backing;
    _ = tracking;

    rows.len = config.num_code_points;
    const items = rows.items(.width);
    const wcwidth_standalone = inputs.items(.wcwidth_standalone);
    const wcwidth_zero_in_grapheme = inputs.items(.wcwidth_zero_in_grapheme);
    const is_emoji_modifier = inputs.items(.is_emoji_modifier);
    const grapheme_break_no_control = inputs.items(.grapheme_break_no_control);

    for (0..config.num_code_points) |i| {
        // This condition is needed as Ghostty currently has a singular
        // concept for the `width` of a code point, while `uucode` splits
        // the concept into `wcwidth_standalone` and
        // `wcwidth_zero_in_grapheme`. The two cases where we want to use
        // the `wcwidth_standalone` despite the code point occupying zero
        // width in a grapheme (`wcwidth_zero_in_grapheme`) are emoji
        // modifiers and prepend code points. For emoji modifiers we want
        // to support displaying them in isolation as color patches, and if
        // prepend characters were to be width 0 they would disappear from
        // the output with Ghostty's current width 0 handling. Future work
        // will take advantage of the uucode `wcwidth_standalone` vs
        // `wcwidth_zero_in_grapheme` split.
        if (wcwidth_zero_in_grapheme[i] and
            !is_emoji_modifier[i] and
            grapheme_break_no_control[i] != .prepend)
        {
            items[i] = 0;
        } else {
            items[i] = @min(2, wcwidth_standalone[i]);
        }
    }
}

const Width = struct {
    pub const build = buildWidth;
};

fn buildIsSymbol(
    comptime InputRow: type,
    comptime Row: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    inputs: config.MultiSlice(InputRow),
    rows: *config.MultiSlice(Row),
    backing: anytype,
    tracking: anytype,
) !void {
    _ = allocator;
    _ = io;
    _ = backing;
    _ = tracking;

    rows.len = config.num_code_points;
    const items = rows.items(.is_symbol);
    const block = inputs.items(.block);
    const general_category = inputs.items(.general_category);

    for (0..config.num_code_points) |i| {
        items[i] = general_category[i] == .other_private_use or
            block[i] == .arrows or
            block[i] == .dingbats or
            block[i] == .emoticons or
            block[i] == .miscellaneous_symbols or
            block[i] == .enclosed_alphanumerics or
            block[i] == .enclosed_alphanumeric_supplement or
            block[i] == .miscellaneous_symbols_and_pictographs or
            block[i] == .transport_and_map_symbols;
    }
}

const IsSymbol = struct {
    pub const build = buildIsSymbol;
};

pub const fields = &config.mergeFields(config.fields, &.{
    .{ .name = "width", .type = u2 },
    .{ .name = "is_symbol", .type = bool },
});

pub const build_components = &config.mergeComponents(config.build_components, &.{
    .{
        .Impl = Width,
        .inputs = &.{
            "wcwidth_standalone",
            "wcwidth_zero_in_grapheme",
            "is_emoji_modifier",
            "grapheme_break_no_control",
        },
        .fields = &.{"width"},
    },
    .{
        .Impl = IsSymbol,
        .inputs = &.{ "block", "general_category" },
        .fields = &.{"is_symbol"},
    },
});

pub const get_components = config.get_components;

pub const tables: []const config.Table = &.{
    .{
        .name = "runtime",
        .fields = &.{
            "is_emoji_presentation",
            "case_folding_full",
            // Not used by ghostty itself -- exposed so this same uucode
            // module instance can also be shared with vaxis (see
            // SharedDeps.zig's vaxis wiring), which needs these three.
            // Sharing one instance (rather than a second, separately
            // -Dexternal_uucode-configured one) avoids two differently
            // -configured modules both rooting at the same vendored
            // src/vendor/uucode/src/root.zig file, which this Zig
            // snapshot rejects.
            "east_asian_width",
            "grapheme_break",
            "general_category",
        },
    },
    .{
        .name = "buildtime",
        .fields = &.{
            "width",
            "wcwidth_zero_in_grapheme",
            "grapheme_break_no_control",
            "is_symbol",
            "is_emoji_vs_base",
        },
    },
};

// -----------------------------------------------------------------------
// Original upstream (uucode v0.2.0 Extension API) content, kept for
// reference/diffing:
//
// const assert = std.debug.assert;
// const config_x = @import("config.x.zig");
// const d = config.default;
// const wcwidth = config_x.wcwidth;
// const grapheme_break_no_control = config_x.grapheme_break_no_control;
//
// const Allocator = std.mem.Allocator;
//
// fn computeWidth(
//     alloc: std.mem.Allocator,
//     cp: u21,
//     data: anytype,
//     backing: anytype,
//     tracking: anytype,
// ) Allocator.Error!void {
//     _ = alloc;
//     _ = cp;
//     _ = backing;
//     _ = tracking;
//
//     if (data.wcwidth_zero_in_grapheme and !data.is_emoji_modifier and data.grapheme_break_no_control != .prepend) {
//         data.width = 0;
//     } else {
//         data.width = @min(2, data.wcwidth_standalone);
//     }
// }
//
// const width = config.Extension{
//     .inputs = &.{
//         "wcwidth_standalone",
//         "wcwidth_zero_in_grapheme",
//         "is_emoji_modifier",
//         "grapheme_break_no_control",
//     },
//     .compute = &computeWidth,
//     .fields = &.{
//         .{ .name = "width", .type = u2 },
//     },
// };
//
// fn computeIsSymbol(
//     alloc: Allocator,
//     cp: u21,
//     data: anytype,
//     backing: anytype,
//     tracking: anytype,
// ) Allocator.Error!void {
//     _ = alloc;
//     _ = cp;
//     _ = backing;
//     _ = tracking;
//     const block = data.block;
//     data.is_symbol = data.general_category == .other_private_use or
//         block == .arrows or
//         block == .dingbats or
//         block == .emoticons or
//         block == .miscellaneous_symbols or
//         block == .enclosed_alphanumerics or
//         block == .enclosed_alphanumeric_supplement or
//         block == .miscellaneous_symbols_and_pictographs or
//         block == .transport_and_map_symbols;
// }
//
// const is_symbol = config.Extension{
//     .inputs = &.{ "block", "general_category" },
//     .compute = &computeIsSymbol,
//     .fields = &.{
//         .{ .name = "is_symbol", .type = bool },
//     },
// };
//
// pub const tables = [_]config.Table{
//     .{
//         .name = "runtime",
//         .extensions = &.{},
//         .fields = &.{
//             d.field("is_emoji_presentation"),
//             d.field("case_folding_full"),
//         },
//     },
//     .{
//         .name = "buildtime",
//         .extensions = &.{
//             wcwidth,
//             grapheme_break_no_control,
//             width,
//             is_symbol,
//         },
//         .fields = &.{
//             width.field("width"),
//             wcwidth.field("wcwidth_zero_in_grapheme"),
//             grapheme_break_no_control.field("grapheme_break_no_control"),
//             is_symbol.field("is_symbol"),
//             d.field("is_emoji_vs_base"),
//         },
//     },
// };

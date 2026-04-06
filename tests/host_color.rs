use kfs::kernel::drivers::vga_text::{vga_text_get_color, vga_text_set_color, VGA_TEXT_DEFAULT_COLOR};
use kfs::kernel::types::screen::{vga_attribute, ColorCode, VgaColor};

#[test]
// This checks that VGA foreground/background nibbles are packed as expected.
fn attribute_packs_foreground_and_background() {
    assert_eq!(vga_attribute(0x02, 0x04), 0x42);
}

#[test]
// This checks that invalid color values are clamped to the low VGA nibble.
fn attribute_masks_values_to_low_nibble() {
    assert_eq!(vga_attribute(0x1f, 0x2a), 0xaf);
}

#[test]
// This checks that the writer default attribute is the repo default green on black.
fn default_attribute_is_green_on_black() {
    assert_eq!(VGA_TEXT_DEFAULT_COLOR.as_u8(), 0x02);
}

#[test]
// This checks the enum mapping for the values most users expect first.
fn enum_color_values_match_vga_codes() {
    assert_eq!(VgaColor::Black.code(), 0x0);
    assert_eq!(VgaColor::Red.code(), 0x4);
}

#[test]
// This checks the index helper can drive color selection in a loop.
fn enum_from_index_wraps_in_palette_range() {
    assert_eq!(VgaColor::from_index(0).code(), 0x0);
    assert_eq!(VgaColor::from_index(4).code(), 0x4);
    assert_eq!(VgaColor::from_index(16).code(), 0x0);
}

#[test]
fn color_api_updates_the_active_writer_attribute() {
    let expected = ColorCode::vga(VgaColor::Red.code(), VgaColor::Black.code());
    vga_text_set_color(VgaColor::Red.code(), VgaColor::Black.code());
    assert_eq!(vga_text_get_color(), expected);

    vga_text_set_color(VgaColor::Green.code(), VgaColor::Black.code());
    assert_eq!(vga_text_get_color(), VGA_TEXT_DEFAULT_COLOR);
}

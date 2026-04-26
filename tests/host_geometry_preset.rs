use kfs::kernel::drivers::vga_text::{VGA_TEXT_HISTORY_CELL_COUNT, VGA_TEXT_HISTORY_DIMENSIONS};
use kfs::kernel::types::screen::{ScreenDimensions, VGA_TEXT_DIMENSIONS};

#[test]
fn vga_text_dimensions_are_fixed_to_standard_vga() {
    assert_eq!(VGA_TEXT_DIMENSIONS, ScreenDimensions::new(80, 25));
    assert_eq!(VGA_TEXT_DIMENSIONS.cell_count(), 2_000);
}

#[test]
fn history_geometry_tracks_the_fixed_visible_width() {
    assert_eq!(VGA_TEXT_HISTORY_DIMENSIONS.width(), VGA_TEXT_DIMENSIONS.width());
    assert_eq!(VGA_TEXT_HISTORY_DIMENSIONS.height(), 256);
    assert_eq!(
        VGA_TEXT_HISTORY_CELL_COUNT,
        VGA_TEXT_HISTORY_DIMENSIONS.cell_count()
    );
}

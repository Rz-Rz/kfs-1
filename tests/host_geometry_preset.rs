use kfs::kernel::types::screen::{
    history_dimensions_for_visible, select_geometry_preset_from_name,
    DEFAULT_SCREEN_GEOMETRY_PRESET, ScreenDimensions, ScreenGeometryPreset, VGA_TEXT_DIMENSIONS,
};
use kfs::kernel::drivers::vga_text::VGA_TEXT_HISTORY_ROWS;

#[cfg(kfs_expect_compact_geometry)]
const EXPECTED_DEFAULT_PRESET: ScreenGeometryPreset = ScreenGeometryPreset::Compact40x10;
#[cfg(not(kfs_expect_compact_geometry))]
const EXPECTED_DEFAULT_PRESET: ScreenGeometryPreset = ScreenGeometryPreset::Vga80x25;

#[test]
fn default_preset_matches_the_current_build_selection() {
    assert_eq!(DEFAULT_SCREEN_GEOMETRY_PRESET, EXPECTED_DEFAULT_PRESET);
    assert_eq!(VGA_TEXT_DIMENSIONS, EXPECTED_DEFAULT_PRESET.geometry());
}

#[test]
fn selecting_compact_preset_changes_the_visible_geometry() {
    let preset = select_geometry_preset_from_name(Some("compact40x10"));

    assert_eq!(preset, ScreenGeometryPreset::Compact40x10);
    assert_eq!(preset.name(), "compact40x10");
    assert_eq!(preset.geometry(), ScreenDimensions::new(40, 10));
}

#[test]
fn history_geometry_tracks_the_selected_visible_preset_width() {
    let preset = select_geometry_preset_from_name(Some("compact40x10"));
    let visible = preset.geometry();
    let history = history_dimensions_for_visible(visible, VGA_TEXT_HISTORY_ROWS);

    assert_eq!(history.width(), visible.width());
    assert_eq!(history.height(), VGA_TEXT_HISTORY_ROWS);
    assert_eq!(history.cell_count(), visible.width() * VGA_TEXT_HISTORY_ROWS);
}

#[test]
fn unknown_preset_names_fall_back_to_the_default_geometry() {
    let preset = select_geometry_preset_from_name(Some("not-a-real-preset"));

    assert_eq!(preset, ScreenGeometryPreset::Vga80x25);
    assert_eq!(preset.geometry(), ScreenDimensions::new(80, 25));
}

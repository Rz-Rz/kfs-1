use kfs::kernel::drivers::vga_text::{
    render_logical_screen_to_physical, screen_render_origin, vga_text_cell, VGA_TEXT_BLANK_BYTE,
    VGA_TEXT_DEFAULT_COLOR,
};
use kfs::kernel::types::screen::{ScreenDimensions, VGA_TEXT_PHYSICAL_DIMENSIONS};

#[test]
fn renderer_centers_compact_rows_without_duplicate_cells() {
    let visible_geometry = ScreenDimensions::new(4, 2);
    let physical_geometry = ScreenDimensions::new(8, 4);
    let top_row = vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'A');
    let second_row = vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'B');
    let blank = vga_text_cell(VGA_TEXT_DEFAULT_COLOR, VGA_TEXT_BLANK_BYTE);
    let logical = [
        top_row, top_row, top_row, top_row, second_row, second_row, second_row, second_row,
    ];
    let mut physical = vec![blank; physical_geometry.cell_count()];

    render_logical_screen_to_physical(
        visible_geometry,
        physical_geometry,
        &logical,
        &mut physical,
        blank,
    );

    let origin = screen_render_origin(visible_geometry, physical_geometry);
    let mut idx: usize = 0;
    while idx < physical_geometry.width() {
        assert_eq!(physical[idx], blank);
        idx += 1;
    }

    let row_one_start = physical_geometry.cell_index(origin.row(), 0);
    assert_eq!(physical[row_one_start], blank);
    assert_eq!(physical[row_one_start + 1], blank);
    assert_eq!(physical[row_one_start + 2], top_row);
    assert_eq!(physical[row_one_start + 5], top_row);
    assert_eq!(physical[row_one_start + 6], blank);
    assert_eq!(physical[row_one_start + 7], blank);

    let row_two_start = physical_geometry.cell_index(origin.row() + 1, 0);
    assert_eq!(physical[row_two_start], blank);
    assert_eq!(physical[row_two_start + 1], blank);
    assert_eq!(physical[row_two_start + 2], second_row);
    assert_eq!(physical[row_two_start + 5], second_row);
    assert_eq!(physical[row_two_start + 6], blank);
    assert_eq!(physical[row_two_start + 7], blank);

    let bottom_row_start = physical_geometry.cell_index(physical_geometry.last_row(), 0);
    idx = bottom_row_start;
    while idx < physical_geometry.cell_count() {
        assert_eq!(physical[idx], blank);
        idx += 1;
    }
}

#[test]
fn screen_render_origin_centers_logical_geometry_inside_physical_vga() {
    let compact = ScreenDimensions::new(40, 10);
    let origin = screen_render_origin(compact, VGA_TEXT_PHYSICAL_DIMENSIONS);

    assert_eq!(origin.row(), 7);
    assert_eq!(origin.col(), 20);
}

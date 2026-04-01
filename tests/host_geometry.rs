use kfs::kernel::drivers::vga_text::{vga_text_blit_viewport, vga_text_scroll_rows_up};
use kfs::kernel::types::screen::ScreenDimensions;

#[test]
fn geometry_reports_dimensions_and_cell_capacity() {
    let geometry = ScreenDimensions::new(40, 10);
    assert_eq!(geometry.width(), 40);
    assert_eq!(geometry.height(), 10);
    assert_eq!(geometry.cell_count(), 400);
    assert_eq!(geometry.row_cells(3), 120);
}

#[test]
fn geometry_clamps_out_of_bounds_positions() {
    let geometry = ScreenDimensions::new(40, 10);
    assert_eq!(geometry.clamp_row(0), 0);
    assert_eq!(geometry.clamp_row(99), 9);
    assert_eq!(geometry.clamp_col(0), 0);
    assert_eq!(geometry.clamp_col(99), 39);
}

#[test]
fn geometry_cell_index_uses_the_configured_width() {
    let geometry = ScreenDimensions::new(40, 10);
    assert_eq!(geometry.cell_index(3, 5), 125);
    assert_eq!(geometry.cell_index(9, 39), 399);
}

#[test]
fn geometry_tail_viewport_top_tracks_the_configured_height() {
    let geometry = ScreenDimensions::new(40, 10);
    assert_eq!(geometry.tail_viewport_top(0), 0);
    assert_eq!(geometry.tail_viewport_top(9), 0);
    assert_eq!(geometry.tail_viewport_top(10), 1);
}

#[test]
fn scroll_rows_up_uses_the_supplied_geometry_width() {
    let geometry = ScreenDimensions::new(4, 3);
    let mut buffer = *b"AAAABBBBCCCC";

    vga_text_scroll_rows_up(&mut buffer, geometry.width(), geometry.height(), b'.');

    assert_eq!(&buffer, b"BBBBCCCC....");
}

#[test]
fn blit_viewport_uses_the_supplied_geometry_dimensions() {
    let geometry = ScreenDimensions::new(4, 3);
    let history = *b"AAAABBBBCCCCDDDD";
    let mut screen = [b'?'; 12];

    vga_text_blit_viewport(
        &history,
        geometry.width(),
        geometry.height(),
        1,
        &mut screen,
        b'.',
    );

    assert_eq!(&screen, b"BBBBCCCCDDDD");
}

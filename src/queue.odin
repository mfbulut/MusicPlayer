package main

import "fx"
import "core:fmt"

draw_queue_sidebar :: proc(x_offset: f32, size: f32) {
	if ui_state.queue_sidebar_anim <= 0 {
		return
	}

	queue_sc := &ui_state.queue_scrollbar
	window_w, window_h := fx.window_size()

	y_offset: f32 = 50

	fx.draw_text("Queue", x_offset + 20, y_offset, 24, set_alpha(UI_TEXT_COLOR, ui_state.queue_sidebar_anim))

	y_offset += 40

	track_count := len(player.queue.tracks)

	list_y := y_offset
	list_h := window_h - y_offset - PLAYER_HEIGHT

	track_height : f32 = 65
	max_scroll := calculate_max_scroll(track_count, track_height, list_h)

	queue_sc.target = clamp(queue_sc.target, 0, max_scroll)
	queue_sc.scroll = clamp(queue_sc.scroll, 0, max_scroll)

	fx.set_scissor(x_offset, list_y, size - 15, list_h)

	if !queue_sc.is_dragging {
		interaction_rect(x_offset, 0, size - 15, list_h)
	}

	track_y := list_y - queue_sc.scroll
	mouse_x, mouse_y := fx.get_mouse()

	for i in 0 ..< track_count {
		track := player.queue.tracks[track_count - 1 - i]

		if track_y > window_h {
			break
		}

		if track_y + 60 > list_y {
			draw_track_item(track, player.queue, x_offset + 15, track_y, size - 45, 60, true)
		}

		track_y += track_height
	}

	fx.disable_scissor()

	if max_scroll > 0 {
		indicator_x := x_offset + size - 12
		indicator_y := list_y + 5
		indicator_h := list_h - 15

		draw_scrollbar(
			queue_sc,
			indicator_x,
			indicator_y,
			4,
			indicator_h,
			max_scroll,
			UI_PRIMARY_COLOR,
			UI_SECONDARY_COLOR,
		)
	}

	if !queue_sc.is_dragging {
		scroll_delta := fx.get_mouse_scroll()
		if scroll_delta != 0 {
			if mouse_x > x_offset && mouse_x < x_offset + size {
				queue_sc.target -= scroll_delta * 80
				queue_sc.target = clamp(queue_sc.target, 0, max_scroll)
			}
		}
	}

	interaction_rect(0, 0, 8000, 8000)
}
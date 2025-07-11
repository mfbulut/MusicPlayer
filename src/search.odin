package main

import "fx"

import "core:fmt"
import "core:hash"
import "core:math"
import "core:slice"
import "core:strings"
import textedit "core:text/edit"
import "core:time"

SearchResult :: struct {
	track: Track,
	score: f32,
}

search_tracks :: proc(query: string) {
	clear(&ui_state.search_results)
	if len(query) == 0 {
		for playlist in playlists {
			for track in playlist.tracks {
				append(&ui_state.search_results, track)
			}
		}
		return
	}

	query_lower := strings.to_lower(query)
	defer delete(query_lower)

	scored_results := make([dynamic]SearchResult)
	defer delete(scored_results)

	for playlist in playlists {
		for track in playlist.tracks {
			selected_title := track.tags.title if track.has_tags && len(track.tags.title) > 0 else track.name
			selected_album := track.tags.album if track.has_tags && len(track.tags.album) > 0 else track.playlist

			track_name_lower    := strings.to_lower(selected_title, context.temp_allocator)
			playlist_name_lower := strings.to_lower(selected_album, context.temp_allocator)

			track_score    := calculate_smart_score(track_name_lower, query_lower)
			playlist_score := calculate_smart_score(playlist_name_lower, query_lower) * 0.8
			final_score    := track_score + playlist_score

			if final_score > 0.1 {
				append(&scored_results, SearchResult{track = track, score = final_score})
			}
		}
	}

	slice.sort_by(scored_results[:], proc(a, b: SearchResult) -> bool {
		return a.score > b.score
	})

	for result in scored_results {
		append(&ui_state.search_results, result.track)
	}
}

calculate_smart_score :: proc(text: string, query: string) -> f32 {
	if len(query) == 0 do return 0
	if len(text) == 0 do return 0

	if text == query {
		return 100.0
	}

	if strings.has_prefix(text, query) {
		return 90.0 + f32(len(query)) / f32(len(text)) * 10.0
	}

	query_words := strings.split(query, " ")
	defer delete(query_words)

	text_words := strings.split(text, " ")
	defer delete(text_words)

	word_match_score := calculate_word_matches(text_words, query_words)
	if word_match_score > 0 {
		return word_match_score
	}

	substring_score := calculate_substring_matches(text, query_words)
	if substring_score > 0 {
		return substring_score
	}

	char_score := calculate_character_fuzzy(text, query)

	return char_score * 0.1
}

calculate_word_matches :: proc(text_words: []string, query_words: []string) -> f32 {
	if len(query_words) == 0 do return 0

	score: f32 = 0
	matched_words := 0

	for query_word in query_words {
		if len(query_word) == 0 do continue

		best_word_score: f32 = 0

		for text_word in text_words {
			if text_word == query_word {

				best_word_score = max(best_word_score, 20.0)
			} else if strings.has_prefix(text_word, query_word) {

				prefix_score := 15.0 + f32(len(query_word)) / f32(len(text_word)) * 5.0
				best_word_score = max(best_word_score, prefix_score)
			} else if strings.contains(text_word, query_word) && len(query_word) > 2 {

				substring_score := 10.0 + f32(len(query_word)) / f32(len(text_word)) * 3.0
				best_word_score = max(best_word_score, substring_score)
			}
		}

		if best_word_score > 0 {
			matched_words += 1
			score += best_word_score
		}
	}

	if matched_words == 0 do return 0


	match_ratio := f32(matched_words) / f32(len(query_words))
	score *= (0.5 + match_ratio * 0.5)

	return score
}

calculate_substring_matches :: proc(text: string, query_words: []string) -> f32 {
	if len(query_words) == 0 do return 0

	score: f32 = 0
	matched_words := 0

	for query_word in query_words {
		if len(query_word) < 3 do continue

		if strings.contains(text, query_word) {
			position := strings.index(text, query_word)

			position_bonus := 1.0 - (f32(position) / f32(len(text))) * 0.3
			word_score := 8.0 * position_bonus + f32(len(query_word)) / f32(len(text)) * 2.0
			score += word_score
			matched_words += 1
		}
	}

	if matched_words == 0 do return 0

	match_ratio := f32(matched_words) / f32(len(query_words))
	score *= (0.3 + match_ratio * 0.7)

	return score
}

calculate_character_fuzzy :: proc(text: string, query: string) -> f32 {
	score: f32 = 0
	query_index := 0
	consecutive_matches := 0
	word_boundary_matches := 0

	for i in 0 ..< len(text) {
		if query_index >= len(query) do break

		if text[i] == query[query_index] {
			score += 1.0

			if i == 0 || text[i - 1] == ' ' || text[i - 1] == '-' || text[i - 1] == '_' {
				word_boundary_matches += 1
				score += 2.0
			}

			if i > 0 && query_index > 0 && text[i - 1] == query[query_index - 1] {
				consecutive_matches += 1
				score += 1.0
			}

			query_index += 1
		}
	}

	if query_index < len(query) do return 0

	normalized_score := score / f32(len(text))
	boundary_bonus := f32(word_boundary_matches) / f32(len(query))

	return normalized_score + boundary_bonus
}

handle_char_input :: proc(char: rune) {
	if ui_state.search_focus {
		switch char {
		case 32 ..= 126:
			textedit.input_rune(&ui_state.search_box, char)
		case 8:
			// Backspace.
			textedit.perform_command(&ui_state.search_box, .Backspace)
		case 127:
			// Ctrl+backspace.
			textedit.perform_command(&ui_state.search_box, .Delete_Word_Left)
		case 27:
			// Escape.
			ui_state.search_focus = false
			fx.set_char_callback(nil)
		case 1:
			// Ctrl+A.
			textedit.perform_command(&ui_state.search_box, .Select_All)
		case 26:
			// Ctrl+Z.
			textedit.perform_command(&ui_state.search_box, .Undo)
		case 25:
			// Ctrl+Y.
			textedit.perform_command(&ui_state.search_box, .Redo)
		case 3:
			// Ctrl+C.
			textedit.perform_command(&ui_state.search_box, .Copy)
		case 22:
			// Ctrl+V.
			textedit.perform_command(&ui_state.search_box, .Paste)
		case 24:
			// Ctrl+X.
			textedit.perform_command(&ui_state.search_box, .Cut)
		}
	}
}

draw_search_view :: proc(x, y, w, h: f32) {
	search_sc   := &ui_state.search_scrollbar

	control_down := fx.key_held(.LEFT_CONTROL) || fx.key_held(.RIGHT_CONTROL)
	shift_down   := fx.key_held(.LEFT_SHIFT) || fx.key_held(.RIGHT_SHIFT)

	if ui_state.search_focus {
		if fx.key_pressed(.LEFT) {
			if control_down {
				if shift_down {
					textedit.perform_command(&ui_state.search_box, .Select_Word_Left)
				} else {
					textedit.perform_command(&ui_state.search_box, .Word_Left)
				}
			} else {
				if shift_down {
					textedit.perform_command(&ui_state.search_box, .Select_Left)
				} else {
					textedit.perform_command(&ui_state.search_box, .Left)
				}
			}
		}

		if fx.key_pressed(.RIGHT) {
			if control_down {
				if shift_down {
					textedit.perform_command(&ui_state.search_box, .Select_Word_Right)
				} else {
					textedit.perform_command(&ui_state.search_box, .Word_Right)
				}
			} else {
				if shift_down {
					textedit.perform_command(&ui_state.search_box, .Select_Right)
				} else {
					textedit.perform_command(&ui_state.search_box, .Right)
				}
			}
		}
	}

	search_query := strings.to_string(ui_state.search_builder)
	textedit.update_time(&ui_state.search_box)

	@(static) last_hash: u64
	if new_hash := hash.fnv64a(transmute([]byte)search_query); new_hash != last_hash {
		search_tracks(search_query)
		last_hash = new_hash
	}

	@(static) last_selection_tick: time.Tick

	TEXT_SIZE :: 16

	search_input_w: f32 = max(min(500, w - 80), fx.measure_text(search_query, TEXT_SIZE) + 50)
	search_input_x := x + (w - search_input_w) / 2
	search_input_y := y + 20

	text_x := search_input_x + 30
	text_y := search_input_y + 10

	is_hovering_input := is_hovering(search_input_x, search_input_y, search_input_w, 40)

	if is_hovering_input {
		fx.set_cursor(.TEXT)
	}

	input_color := ui_state.search_focus ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR
	fx.draw_rect_rounded(search_input_x, search_input_y, search_input_w, 40, 8, input_color)
	fx.draw_texture(search_icon, search_input_x + 10, search_input_y + 12, 14, 14, fx.WHITE)

	if fx.mouse_held(.LEFT) {
		if fx.mouse_pressed(.LEFT) {
			ui_state.search_focus = is_hovering_input
		}

		if ui_state.search_focus {
			fx.set_char_callback(handle_char_input)

			mouse_x, _ := fx.get_mouse()
			// Tolerance of 50% allows selections to round from the middle of characters.
			_, fits := fx.measure_text_fits(search_query, TEXT_SIZE, f32(mouse_x) - text_x, 0.5)

			if fx.mouse_pressed(.LEFT) {
				// Initial click empties selection, moves cursor to location.
				ui_state.search_box.selection = {fits, fits}
				last_selection_tick = time.tick_now()
			} else {
				// Further dragging moves one end of the selection.
				ui_state.search_box.selection[0] = fits
			}
		} else {
			fx.set_char_callback(nil)
			ui_state.search_box.selection = {len(search_query), len(search_query)}
		}
	}

	select_l := fx.measure_text(search_query[:ui_state.search_box.selection[0]], TEXT_SIZE)
	select_r := fx.measure_text(search_query[:ui_state.search_box.selection[1]], TEXT_SIZE)

	if textedit.has_selection(&ui_state.search_box) {
		// Selection background.
		color := darken(UI_SECONDARY_COLOR, 30)
		fx.draw_rect_rounded(text_x + select_l - 1, text_y - 4, select_r - select_l + 2, TEXT_SIZE + 7.5, 4, color)
	} else if ui_state.search_focus {
		// Focus blip.
		off := time.tick_since(last_selection_tick)
		alpha := math.sin(time.duration_seconds(off) * 5) * 0.5 + 0.5
		color := lerp_color(UI_TEXT_COLOR, input_color, f32(alpha))
		fx.draw_rect(text_x + select_r, text_y, 2, TEXT_SIZE, color)
	}

	if len(search_query) > 0 || ui_state.search_focus {
		fx.draw_text(search_query, text_x, text_y, TEXT_SIZE, UI_TEXT_COLOR)
	} else {
		fx.draw_text("Search tracks and playlists...", text_x, text_y, TEXT_SIZE, UI_TEXT_SECONDARY)
	}

	results_y := search_input_y + 80
	results_h := h - (results_y - y)

	result_count := len(ui_state.search_results)
	track_height : f32 = 65
	max_scroll := calculate_max_scroll(result_count, track_height, results_h)

	search_sc.target = clamp(search_sc.target, 0, max_scroll)
	search_sc.scroll = clamp(search_sc.scroll, 0, max_scroll)

	if result_count > 0 {
		fx.draw_text_aligned(
			fmt.tprintf("%d results", result_count),
			search_input_x + search_input_w / 2,
			results_y - 30,
			16,
			UI_TEXT_SECONDARY,
			.CENTER,
		)

		fx.set_scissor(x, results_y, w - 15, results_h)

		if !search_sc.is_dragging {
			interaction_rect(x, results_y, w - 15, results_h)
		}

		track_y := results_y - search_sc.scroll

		for track, _ in ui_state.search_results {
			if track_y > y + h {
				break
			}

			if track_y + 60 > results_y {
				draw_track_item(
					track,
					find_playlist_by_name(track.playlist)^,
					x + 30,
					track_y,
					w - 70,
					60,
				)
			}

			track_y += track_height
		}

		fx.disable_scissor()

		if max_scroll > 0 {
			indicator_x := x + w - 20
			indicator_y := results_y + 5
			indicator_h := results_h - 10

			draw_scrollbar(
				search_sc,
				indicator_x,
				indicator_y,
				4,
				indicator_h,
				max_scroll,
				UI_PRIMARY_COLOR,
				UI_SECONDARY_COLOR,
			)
		}

		if !search_sc.is_dragging {
			window_w, window_h := fx.window_size()
			interaction_rect(0, 0, window_w, window_h)

			scroll_delta := fx.get_mouse_scroll()
			if scroll_delta != 0 {
				mouse_x, mouse_y := fx.get_mouse()
				if mouse_x > x && mouse_y < y + h {
					search_sc.target -= scroll_delta * 80
					search_sc.target = clamp(search_sc.target, 0, max_scroll)
				}
			}
		}
	} else if len(search_query) > 0 {
		fx.draw_text_aligned("No results found", search_input_x + search_input_w / 2, search_input_y + 60, 18, UI_TEXT_SECONDARY, .CENTER)
	}
}

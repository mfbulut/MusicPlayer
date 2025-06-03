package main

import fx "../fx"

import "core:fmt"
import "core:strings"
import "core:slice"

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
            track_name_lower := strings.to_lower(track.name)
            playlist_name_lower := strings.to_lower(track.playlist)
            defer delete(track_name_lower)
            defer delete(playlist_name_lower)

            track_score := calculate_fuzzy_score(track_name_lower, query_lower)
            playlist_score := calculate_fuzzy_score(playlist_name_lower, query_lower) * 0.7

            final_score := max(track_score, playlist_score)

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

calculate_fuzzy_score :: proc(text: string, query: string) -> f32 {
    if len(query) == 0 {
        return 0
    }
    if len(text) == 0 {
        return 0
    }

    score: f32 = 0
    query_index := 0
    consecutive_matches := 0
    start_bonus := false

    if strings.has_prefix(text, query) {
        return 1.0 + f32(len(query)) / f32(len(text))
    }

    words := strings.split(text, " ")
    defer delete(words)

    for word in words {
        if strings.has_prefix(word, query) {
            return 0.9 + f32(len(query)) / f32(len(word))
        }
    }

    for i in 0..<len(text) {
        if query_index >= len(query) {
            break
        }

        if text[i] == query[query_index] {
            if query_index == 0 {

                if i == 0 || text[i-1] == ' ' || text[i-1] == '-' || text[i-1] == '_' {
                    start_bonus = true
                    score += 0.15
                }
            }

            score += 0.1
            consecutive_matches += 1
            query_index += 1

            if consecutive_matches > 1 {
                score += 0.05 * f32(consecutive_matches)
            }
        } else {
            consecutive_matches = 0
        }
    }

    if query_index == len(query) {
        score += 0.2

        match_density := f32(len(query)) / f32(len(text))
        score += match_density * 0.3

        if start_bonus {
            score += 0.2
        }
    } else {
        completion_ratio := f32(query_index) / f32(len(query))
        score *= completion_ratio
    }

    return score
}

handle_char_input :: proc(char: u8) {
    if ui_state.search_focus {
        if char >= 32 && char <= 126 {
            ui_state.search_query = strings.concatenate({ui_state.search_query, string([]u8{char})})
            search_tracks(ui_state.search_query)
        }
    }
}

draw_search_view :: proc(x, y, w, h: f32) {
    search_input_w: f32 = min(500, w - 80)
    search_input_x := x + (w - search_input_w) / 2
    search_input_y := y + 20

    is_hovering_input := is_hovering(search_input_x, search_input_y, search_input_w, 40)

    if is_hovering_input {
        fx.set_cursor(.TEXT)
    }

    input_color := ui_state.search_focus ? UI_HOVER_COLOR : UI_SECONDARY_COLOR
    fx.draw_rounded_rect(search_input_x, search_input_y, search_input_w, 40, 8, input_color)

    fx.use_texture(search_icon)
    fx.draw_texture(search_input_x + 10, search_input_y + 13, 14, 14, fx.WHITE)

    if len(ui_state.search_query) > 0 || ui_state.search_focus {
        fx.draw_text(string(ui_state.search_query), search_input_x + 30, search_input_y + 9, 16, UI_TEXT_COLOR)
    } else {
        fx.draw_text("Type to search tracks and playlists...", search_input_x + 30, search_input_y + 9, 16, UI_TEXT_SECONDARY)
    }

    if fx.mouse_pressed(.LEFT) {
        ui_state.search_focus = is_hovering_input
        if ui_state.search_focus {
            fx.set_char_callback(handle_char_input)
        } else {
            fx.set_char_callback(nil)
        }
    }

    if fx.key_pressed(.BACKSPACE) && len(ui_state.search_query) > 0 {
        if len(ui_state.search_query) > 0 {
            ui_state.search_query = ui_state.search_query[:len(ui_state.search_query)-1]
            search_tracks(ui_state.search_query)
        }

        if fx.key_held(.LEFT_CONTROL) {
            ui_state.search_query = ""
            search_tracks(ui_state.search_query)
        }
    }

    results_y := search_input_y + 75
    results_h := h - (results_y - y)

    result_count := len(ui_state.search_results)
    track_height: f32 = 65
    search_max_scroll := calculate_max_scroll(result_count, track_height, results_h)

    ui_state.search_scrollbar.target = clamp(ui_state.search_scrollbar.target, 0, search_max_scroll)
    ui_state.search_scrollbar.scroll = clamp(ui_state.search_scrollbar.scroll, 0, search_max_scroll)

    if result_count > 0 {
        fx.draw_text_aligned(fmt.tprintf("%d results", result_count), search_input_x + search_input_w / 2, results_y - 30, 16, UI_TEXT_SECONDARY, .CENTER)

        fx.set_scissor(i32(x), i32(results_y), i32(w - 15), i32(results_h))

        if !ui_state.search_scrollbar.is_dragging {
            interaction_rect(x, results_y, w - 15, results_h)
        }

        track_y := results_y - ui_state.search_scrollbar.scroll

        for track, i in ui_state.search_results {
            if track_y > y + h {
                break
            }

            if track_y + 60 > results_y {
                draw_track_item(track, find_playlist_by_name(track.playlist), x + 20, track_y, w - 45, 60)
            }

            track_y += track_height
        }

        fx.disable_scissor()

        if search_max_scroll > 0 {
            indicator_x := x + w - 15
            indicator_y := results_y + 5
            indicator_h := results_h - 10

            draw_scrollbar(&ui_state.search_scrollbar, indicator_x, indicator_y, 4, indicator_h, search_max_scroll, UI_PRIMARY_COLOR, UI_ACCENT_COLOR)
        }

        if !ui_state.search_scrollbar.is_dragging {
            window_w, window_h := fx.window_size()
            interaction_rect(0, 0, f32(window_w), f32(window_h))

            scroll_delta := fx.get_mouse_scroll()
            if scroll_delta != 0 {
                mouse_x, _ := fx.get_mouse()
                if f32(mouse_x) > x {
                    ui_state.search_scrollbar.target -= f32(scroll_delta) * 80
                    ui_state.search_scrollbar.target = clamp(ui_state.search_scrollbar.target, 0, search_max_scroll)
                }
            }
        }
    } else if len(ui_state.search_query) > 0 {
        fx.draw_text("No results found", search_input_x, results_y + 50, 18, UI_TEXT_SECONDARY)
    }
}
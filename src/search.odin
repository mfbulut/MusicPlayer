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

            track_score := calculate_smart_score(track_name_lower, query_lower)
            playlist_score := calculate_smart_score(playlist_name_lower, query_lower) * 0.8

            final_score := max(track_score, playlist_score)

            if final_score > 0.01 {
                append(&scored_results, SearchResult{track = track, score = final_score})
            }

            delete(track_name_lower)
            delete(playlist_name_lower)
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

    for i in 0..<len(text) {
        if query_index >= len(query) do break

        if text[i] == query[query_index] {
            score += 1.0

            if i == 0 || text[i-1] == ' ' || text[i-1] == '-' || text[i-1] == '_' {
                word_boundary_matches += 1
                score += 2.0
            }

            if i > 0 && query_index > 0 && text[i-1] == query[query_index-1] {
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

    input_color := ui_state.search_focus ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR
    fx.draw_rect_rounded(search_input_x, search_input_y, search_input_w, 40, 8, input_color)

    fx.draw_texture(search_icon, search_input_x + 10, search_input_y + 13, 14, 14, fx.WHITE)

    if len(ui_state.search_query) > 0 || ui_state.search_focus {
        fx.draw_text(fmt.tprintf("%s|", ui_state.search_query), search_input_x + 30, search_input_y + 9, 16, UI_TEXT_COLOR)
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

    results_y := search_input_y + 80
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

        for track, _ in ui_state.search_results {
            if track_y > y + h {
                break
            }

            if track_y + 60 > results_y {
                draw_track_item(track, find_playlist_by_name(track.playlist), x + 30, track_y, w - 70, 60)
            }

            track_y += track_height
        }

        fx.disable_scissor()

        if search_max_scroll > 0 {
            indicator_x := x + w - 20
            indicator_y := results_y + 5
            indicator_h := results_h - 10

            draw_scrollbar(&ui_state.search_scrollbar, indicator_x, indicator_y, 4, indicator_h, search_max_scroll, UI_PRIMARY_COLOR, UI_SECONDARY_COLOR)
        }

        if !ui_state.search_scrollbar.is_dragging {
            window_w, window_h := fx.window_size()
            interaction_rect(0, 0, f32(window_w), f32(window_h))

            scroll_delta := fx.get_mouse_scroll()
            if scroll_delta != 0 {
                mouse_x, mouse_y := fx.get_mouse()
                if f32(mouse_x) > x && f32(mouse_y) < y + h {
                    ui_state.search_scrollbar.target -= f32(scroll_delta) * 80
                    ui_state.search_scrollbar.target = clamp(ui_state.search_scrollbar.target, 0, search_max_scroll)
                }
            }
        }
    } else if len(ui_state.search_query) > 0 {
        fx.draw_text("No results found", search_input_x, results_y + 50, 18, UI_TEXT_SECONDARY)
    }
}
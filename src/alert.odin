package main

import "fx"

Alert :: struct {
	image:              fx.Texture,
	title:              string,
	description:        string,
	is_visible:         bool,
	animation_progress: f32,
	target_progress:    f32,
	show_time:          f32,
	duration:           f32,
}

g_alert: Alert
ALERT_ANIMATION_SPEED :: 12.0
ALERT_DEFAULT_DURATION :: 3.0

show_alert :: proc(
	image: fx.Texture,
	title: string,
	description: string,
	duration: f32 = ALERT_DEFAULT_DURATION,
) {
	g_alert.image = image
	g_alert.title = title
	g_alert.description = description
	g_alert.is_visible = true
	g_alert.target_progress = 1.0
	g_alert.show_time = 0.0
	g_alert.duration = duration
}

update_alert :: proc(dt: f32) {
	if !g_alert.is_visible && g_alert.animation_progress <= 0.0 {
		return
	}

	if abs(g_alert.target_progress - g_alert.animation_progress) > 0.01 {
		g_alert.animation_progress +=
			(g_alert.target_progress - g_alert.animation_progress) * ALERT_ANIMATION_SPEED * dt
	} else {
		g_alert.animation_progress = g_alert.target_progress
	}

	if g_alert.is_visible {
		g_alert.show_time += dt
		if g_alert.show_time >= g_alert.duration {
			g_alert.is_visible = false
			g_alert.target_progress = 0.0
		}
	}

	if !g_alert.is_visible && g_alert.animation_progress <= 0.01 {
		g_alert.animation_progress = 0.0
	}
}

draw_alert :: proc() {
	if g_alert.animation_progress <= 0.0 {
		return
	}

	window_w, window_h := fx.window_size()
	screen_w := window_w
	screen_h := window_h

	alert_w : f32 = 350
	alert_h : f32 = 70
	padding : f32 = 20

	alert_x := screen_w - alert_w - padding + (1.0 - g_alert.animation_progress) * (alert_w + padding)
	alert_y := screen_h - alert_h - padding - 75

	bg_color := set_alpha(brighten(UI_PRIMARY_COLOR, 20), min(g_alert.animation_progress, 0.9))

	fx.draw_gradient_rect_rounded_vertical(
		alert_x,
		alert_y,
		alert_w,
		alert_h,
		12,
		brighten(bg_color, 15),
		bg_color,
	)

	content_x := alert_x + 15
	content_y := alert_y + 15

	title_color := set_alpha(fx.Color{255, 255, 255, 255}, g_alert.animation_progress)

	image_size : f32 = 50

	if g_alert.image.width != 0 {
		fx.draw_texture_rounded(
			g_alert.image,
			content_x,
			content_y + (alert_h - 30 - image_size) / 2,
			image_size,
			image_size,
			8,
			title_color,
		)
		content_x += image_size + 15
	}

	text_area_w := alert_w - (content_x - alert_x) - 20

	if len(g_alert.title) > 0 {
		title_text := truncate_text(g_alert.title, text_area_w, 18)
		fx.draw_text(title_text, content_x, content_y, 18, title_color)
		content_y += 25
	}

	desc_color := set_alpha(fx.Color{200, 200, 215, 255}, g_alert.animation_progress)
	if len(g_alert.description) > 0 {
		desc_text := truncate_text(g_alert.description, text_area_w, 14)
		fx.draw_text(desc_text, content_x, content_y, 14, desc_color)
	}
}

hide_alert :: proc() {
	g_alert.is_visible = false
	g_alert.target_progress = 0.0
}

is_alert_visible :: proc() -> bool {
	return g_alert.animation_progress > 0.0
}
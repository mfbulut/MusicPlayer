package fx

import "core:math"

Color :: struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,
}

LIGHTGRAY :: Color{200, 200, 200, 255}
GRAY :: Color{130, 130, 130, 255}
DARKGRAY :: Color{80, 80, 80, 255}
YELLOW :: Color{253, 249, 0, 255}
GOLD :: Color{255, 203, 0, 255}
ORANGE :: Color{255, 161, 0, 255}
PINK :: Color{255, 109, 194, 255}
RED :: Color{230, 41, 55, 255}
MAROON :: Color{190, 33, 55, 255}
GREEN :: Color{0, 228, 48, 255}
LIME :: Color{0, 158, 47, 255}
DARKGREEN :: Color{0, 117, 44, 255}
SKYBLUE :: Color{102, 191, 255, 255}
BLUE :: Color{0, 121, 241, 255}
DARKBLUE :: Color{0, 82, 172, 255}
PURPLE :: Color{200, 122, 255, 255}
VIOLET :: Color{135, 60, 190, 255}
DARKPURPLE :: Color{112, 31, 126, 255}
BEIGE :: Color{211, 176, 131, 255}
BROWN :: Color{127, 106, 79, 255}
DARKBROWN :: Color{76, 63, 47, 255}

WHITE :: Color{255, 255, 255, 255}
BLACK :: Color{0, 0, 0, 255}
BLANK :: Color{0, 0, 0, 0}
MAGENTA :: Color{255, 0, 255, 255}

Vertex :: struct {
	posision: [2]f32,
	texture:  [2]f32,
	color:    Color,
}

MAX_VERTICIES :: 2048
verticies: [MAX_VERTICIES]Vertex
verticies_count: int

draw_rect :: proc(x, y, w, h: f32, color: Color) {
	if ctx.is_minimized do return

	verts := []Vertex {
		Vertex{{x, y}, {-1.0, 0.0}, color},
		Vertex{{x, y + h}, {-1.0, 0.0}, color},
		Vertex{{x + w, y + h}, {-1.0, 0.0}, color},
		Vertex{{x, y}, {-1.0, 0.0}, color},
		Vertex{{x + w, y + h}, {-1.0, 0.0}, color},
		Vertex{{x + w, y}, {-1.0, 0.0}, color},
	}

	copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
	verticies_count += len(verts)
}


draw_texture :: proc(texture: Texture, x, y, w, h: f32, color: Color) {
	if ctx.is_minimized do return

	use_texture(texture)

	verts := []Vertex {
		Vertex{{x, y}, {0.0, 0.0}, color},
		Vertex{{x, y + h}, {0.0, 1.0}, color},
		Vertex{{x + w, y + h}, {1.0, 1.0}, color},
		Vertex{{x, y}, {0.0, 0.0}, color},
		Vertex{{x + w, y + h}, {1.0, 1.0}, color},
		Vertex{{x + w, y}, {1.0, 0.0}, color},
	}

	copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
	verticies_count += len(verts)
}

draw_texture_cropped :: proc(texture: Texture, x, y, w, h: f32, color: Color) {
	if ctx.is_minimized do return

	tex_w := f32(texture.width)
	tex_h := f32(texture.height)

	if tex_w <= 0 || tex_h <= 0 do return

	tex_aspect := tex_w / tex_h
	target_aspect := w / h

	scaled_w, scaled_h: f32

	if tex_aspect > target_aspect {
		scaled_h = h
		scaled_w = h * tex_aspect
	} else {
		scaled_w = w
		scaled_h = w / tex_aspect
	}

	offset_x := (w - scaled_w) * 0.5
	offset_y := (h - scaled_h) * 0.5

	final_x := x + offset_x
	final_y := y + offset_y

	draw_texture(texture, final_x, final_y, scaled_w, scaled_h, color)
}

draw_circle :: proc(center_x, center_y, radius: f32, color: Color, segments: int = 32) {
	if ctx.is_minimized do return

	center := Vertex{{center_x, center_y}, {-1.0, 0.0}, color}

	angle_step := 2.0 * math.PI / f32(segments)

	for i in 0 ..< segments {
		angle1 := f32(i) * angle_step
		angle2 := f32((i + 1) % segments) * angle_step

		x1 := center_x + radius * math.cos(angle1)
		y1 := center_y + radius * math.sin(angle1)
		x2 := center_x + radius * math.cos(angle2)
		y2 := center_y + radius * math.sin(angle2)

		verts := []Vertex {
			center,
			Vertex{{x1, y1}, {-1.0, 0.0}, color},
			Vertex{{x2, y2}, {-1.0, 0.0}, color},
		}

		copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
		verticies_count += len(verts)
	}
}

draw_line :: proc(x1, y1, x2, y2, thickness: f32, color: Color) {
	if ctx.is_minimized do return

	// Calculate direction vector
	dx := x2 - x1
	dy := y2 - y1
	length := math.sqrt(dx * dx + dy * dy)

	if length < 0.001 do return // Avoid division by zero for very short lines

	// Normalize direction vector
	norm_dx := dx / length
	norm_dy := dy / length

	// Calculate perpendicular vector for thickness
	perp_x := -norm_dy * thickness * 0.5
	perp_y := norm_dx * thickness * 0.5

	// Calculate the four corners of the line rectangle
	corner1_x := x1 + perp_x
	corner1_y := y1 + perp_y
	corner2_x := x1 - perp_x
	corner2_y := y1 - perp_y
	corner3_x := x2 - perp_x
	corner3_y := y2 - perp_y
	corner4_x := x2 + perp_x
	corner4_y := y2 + perp_y

	// Create two triangles to form the line rectangle
	verts := []Vertex {
		// First triangle
		Vertex{{corner1_x, corner1_y}, {-1.0, 0.0}, color},
		Vertex{{corner2_x, corner2_y}, {-1.0, 0.0}, color},
		Vertex{{corner3_x, corner3_y}, {-1.0, 0.0}, color},

		// Second triangle
		Vertex{{corner1_x, corner1_y}, {-1.0, 0.0}, color},
		Vertex{{corner3_x, corner3_y}, {-1.0, 0.0}, color},
		Vertex{{corner4_x, corner4_y}, {-1.0, 0.0}, color},
	}

	copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
	verticies_count += len(verts)
}

draw_rect_rounded :: proc(x, y, w, h, radius: f32, color: Color, corner_segments: int = 8) {
	if ctx.is_minimized do return

	max_radius := min(w, h) * 0.5
	clamped_radius := min(radius, max_radius)

	if clamped_radius <= 0 {
		draw_rect(x, y, w, h, color)
		return
	}


	corners := [4][2]f32 {
		{x + clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + h - clamped_radius},
		{x + clamped_radius, y + h - clamped_radius},
	}


	corner_angles := [4][2]f32 {
		{math.PI, 3.0 * math.PI / 2.0},
		{3.0 * math.PI / 2.0, 2.0 * math.PI},
		{0.0, math.PI / 2.0},
		{math.PI / 2.0, math.PI},
	}


	for corner_idx in 0 ..< 4 {
		corner_center := corners[corner_idx]
		start_angle := corner_angles[corner_idx][0]
		end_angle := corner_angles[corner_idx][1]

		angle_step := (end_angle - start_angle) / f32(corner_segments)

		for i in 0 ..< corner_segments {
			angle1 := start_angle + f32(i) * angle_step
			angle2 := start_angle + f32(i + 1) * angle_step

			x1 := corner_center.x + clamped_radius * math.cos(angle1)
			y1 := corner_center.y + clamped_radius * math.sin(angle1)
			x2 := corner_center.x + clamped_radius * math.cos(angle2)
			y2 := corner_center.y + clamped_radius * math.sin(angle2)

			verts := []Vertex {
				Vertex{{corner_center.x, corner_center.y}, {-1.0, 0.0}, color},
				Vertex{{x1, y1}, {-1.0, 0.0}, color},
				Vertex{{x2, y2}, {-1.0, 0.0}, color},
			}

			copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
			verticies_count += len(verts)
		}
	}

	inner_w := w - 2.0 * clamped_radius
	inner_h := h - 2.0 * clamped_radius

	if inner_w > 0 && inner_h > 0 {
		center_verts := []Vertex {
			Vertex{{x + clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
		}

		copy(verticies[verticies_count:verticies_count + len(center_verts)], center_verts[:])
		verticies_count += len(center_verts)
	}


	if inner_w > 0 {

		top_verts := []Vertex {
			Vertex{{x + clamped_radius, y}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y}, {-1.0, 0.0}, color},
		}

		copy(verticies[verticies_count:verticies_count + len(top_verts)], top_verts[:])
		verticies_count += len(top_verts)


		bottom_verts := []Vertex {
			Vertex{{x + clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y + h}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + h}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + h}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
		}

		copy(verticies[verticies_count:verticies_count + len(bottom_verts)], bottom_verts[:])
		verticies_count += len(bottom_verts)
	}


	if inner_h > 0 {
		left_verts := []Vertex {
			Vertex{{x, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
		}

		copy(verticies[verticies_count:verticies_count + len(left_verts)], left_verts[:])
		verticies_count += len(left_verts)

		right_verts := []Vertex {
			Vertex{{x + w - clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w - clamped_radius, y + clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w, y + h - clamped_radius}, {-1.0, 0.0}, color},
			Vertex{{x + w, y + clamped_radius}, {-1.0, 0.0}, color},
		}

		copy(verticies[verticies_count:verticies_count + len(right_verts)], right_verts[:])
		verticies_count += len(right_verts)
	}
}

draw_texture_rounded :: proc(
	texture: Texture,
	x, y, w, h, radius: f32,
	color: Color,
	corner_segments: int = 8,
) {
	if ctx.is_minimized do return

	max_radius := min(w, h) * 0.5
	clamped_radius := min(radius, max_radius)

	if clamped_radius <= 0 {
		draw_texture(texture, x, y, w, h, color)
		return
	} else {
		use_texture(texture)
	}

	calc_tex_coord :: proc(px, py, rect_x, rect_y, rect_w, rect_h: f32) -> [2]f32 {
		u := (px - rect_x) / rect_w
		v := (py - rect_y) / rect_h
		return {u, v}
	}

	corners := [4][2]f32 {
		{x + clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + h - clamped_radius},
		{x + clamped_radius, y + h - clamped_radius},
	}


	corner_angles := [4][2]f32 {
		{math.PI, 3.0 * math.PI / 2.0},
		{3.0 * math.PI / 2.0, 2.0 * math.PI},
		{0.0, math.PI / 2.0},
		{math.PI / 2.0, math.PI},
	}


	for corner_idx in 0 ..< 4 {
		corner_center := corners[corner_idx]
		start_angle := corner_angles[corner_idx][0]
		end_angle := corner_angles[corner_idx][1]

		angle_step := (end_angle - start_angle) / f32(corner_segments)


		center_tex := calc_tex_coord(corner_center.x, corner_center.y, x, y, w, h)

		for i in 0 ..< corner_segments {
			angle1 := start_angle + f32(i) * angle_step
			angle2 := start_angle + f32(i + 1) * angle_step

			x1 := corner_center.x + clamped_radius * math.cos(angle1)
			y1 := corner_center.y + clamped_radius * math.sin(angle1)
			x2 := corner_center.x + clamped_radius * math.cos(angle2)
			y2 := corner_center.y + clamped_radius * math.sin(angle2)


			tex1 := calc_tex_coord(x1, y1, x, y, w, h)
			tex2 := calc_tex_coord(x2, y2, x, y, w, h)

			verts := []Vertex {
				Vertex{{corner_center.x, corner_center.y}, center_tex, color},
				Vertex{{x1, y1}, tex1, color},
				Vertex{{x2, y2}, tex2, color},
			}

			copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
			verticies_count += len(verts)
		}
	}


	inner_w := w - 2.0 * clamped_radius
	inner_h := h - 2.0 * clamped_radius


	if inner_w > 0 && inner_h > 0 {
		center_x1 := x + clamped_radius
		center_y1 := y + clamped_radius
		center_x2 := x + w - clamped_radius
		center_y2 := y + h - clamped_radius

		center_verts := []Vertex {
			Vertex {
				{center_x1, center_y1},
				calc_tex_coord(center_x1, center_y1, x, y, w, h),
				color,
			},
			Vertex {
				{center_x1, center_y2},
				calc_tex_coord(center_x1, center_y2, x, y, w, h),
				color,
			},
			Vertex {
				{center_x2, center_y2},
				calc_tex_coord(center_x2, center_y2, x, y, w, h),
				color,
			},
			Vertex {
				{center_x1, center_y1},
				calc_tex_coord(center_x1, center_y1, x, y, w, h),
				color,
			},
			Vertex {
				{center_x2, center_y2},
				calc_tex_coord(center_x2, center_y2, x, y, w, h),
				color,
			},
			Vertex {
				{center_x2, center_y1},
				calc_tex_coord(center_x2, center_y1, x, y, w, h),
				color,
			},
		}

		copy(verticies[verticies_count:verticies_count + len(center_verts)], center_verts[:])
		verticies_count += len(center_verts)
	}


	if inner_w > 0 {

		top_x1 := x + clamped_radius
		top_y1 := y
		top_x2 := x + w - clamped_radius
		top_y2 := y + clamped_radius

		top_verts := []Vertex {
			Vertex{{top_x1, top_y1}, calc_tex_coord(top_x1, top_y1, x, y, w, h), color},
			Vertex{{top_x1, top_y2}, calc_tex_coord(top_x1, top_y2, x, y, w, h), color},
			Vertex{{top_x2, top_y2}, calc_tex_coord(top_x2, top_y2, x, y, w, h), color},
			Vertex{{top_x1, top_y1}, calc_tex_coord(top_x1, top_y1, x, y, w, h), color},
			Vertex{{top_x2, top_y2}, calc_tex_coord(top_x2, top_y2, x, y, w, h), color},
			Vertex{{top_x2, top_y1}, calc_tex_coord(top_x2, top_y1, x, y, w, h), color},
		}

		copy(verticies[verticies_count:verticies_count + len(top_verts)], top_verts[:])
		verticies_count += len(top_verts)


		bottom_x1 := x + clamped_radius
		bottom_y1 := y + h - clamped_radius
		bottom_x2 := x + w - clamped_radius
		bottom_y2 := y + h

		bottom_verts := []Vertex {
			Vertex {
				{bottom_x1, bottom_y1},
				calc_tex_coord(bottom_x1, bottom_y1, x, y, w, h),
				color,
			},
			Vertex {
				{bottom_x1, bottom_y2},
				calc_tex_coord(bottom_x1, bottom_y2, x, y, w, h),
				color,
			},
			Vertex {
				{bottom_x2, bottom_y2},
				calc_tex_coord(bottom_x2, bottom_y2, x, y, w, h),
				color,
			},
			Vertex {
				{bottom_x1, bottom_y1},
				calc_tex_coord(bottom_x1, bottom_y1, x, y, w, h),
				color,
			},
			Vertex {
				{bottom_x2, bottom_y2},
				calc_tex_coord(bottom_x2, bottom_y2, x, y, w, h),
				color,
			},
			Vertex {
				{bottom_x2, bottom_y1},
				calc_tex_coord(bottom_x2, bottom_y1, x, y, w, h),
				color,
			},
		}

		copy(verticies[verticies_count:verticies_count + len(bottom_verts)], bottom_verts[:])
		verticies_count += len(bottom_verts)
	}


	if inner_h > 0 {

		left_x1 := x
		left_y1 := y + clamped_radius
		left_x2 := x + clamped_radius
		left_y2 := y + h - clamped_radius

		left_verts := []Vertex {
			Vertex{{left_x1, left_y1}, calc_tex_coord(left_x1, left_y1, x, y, w, h), color},
			Vertex{{left_x1, left_y2}, calc_tex_coord(left_x1, left_y2, x, y, w, h), color},
			Vertex{{left_x2, left_y2}, calc_tex_coord(left_x2, left_y2, x, y, w, h), color},
			Vertex{{left_x1, left_y1}, calc_tex_coord(left_x1, left_y1, x, y, w, h), color},
			Vertex{{left_x2, left_y2}, calc_tex_coord(left_x2, left_y2, x, y, w, h), color},
			Vertex{{left_x2, left_y1}, calc_tex_coord(left_x2, left_y1, x, y, w, h), color},
		}

		copy(verticies[verticies_count:verticies_count + len(left_verts)], left_verts[:])
		verticies_count += len(left_verts)


		right_x1 := x + w - clamped_radius
		right_y1 := y + clamped_radius
		right_x2 := x + w
		right_y2 := y + h - clamped_radius

		right_verts := []Vertex {
			Vertex{{right_x1, right_y1}, calc_tex_coord(right_x1, right_y1, x, y, w, h), color},
			Vertex{{right_x1, right_y2}, calc_tex_coord(right_x1, right_y2, x, y, w, h), color},
			Vertex{{right_x2, right_y2}, calc_tex_coord(right_x2, right_y2, x, y, w, h), color},
			Vertex{{right_x1, right_y1}, calc_tex_coord(right_x1, right_y1, x, y, w, h), color},
			Vertex{{right_x2, right_y2}, calc_tex_coord(right_x2, right_y2, x, y, w, h), color},
			Vertex{{right_x2, right_y1}, calc_tex_coord(right_x2, right_y1, x, y, w, h), color},
		}

		copy(verticies[verticies_count:verticies_count + len(right_verts)], right_verts[:])
		verticies_count += len(right_verts)
	}
}

draw_texture_rounded_cropped :: proc(
	texture: Texture,
	x, y, w, h, radius: f32,
	color: Color,
	corner_segments: int = 8,
) {
	if ctx.is_minimized do return

	max_radius := min(w, h) * 0.5
	clamped_radius := min(radius, max_radius)

	if clamped_radius <= 0 {
		draw_texture_cropped(texture, x, y, w, h, color)
		return
	} else {
		use_texture(texture)
	}

	// Calculate aspect ratios
	texture_aspect := f32(texture.width) / f32(texture.height)
	target_aspect := w / h

	// Calculate texture coordinates for cropping
	tex_x, tex_y, tex_w, tex_h: f32

	if texture_aspect > target_aspect {
		// Texture is wider - crop horizontally
		tex_h = 1.0
		tex_w = target_aspect / texture_aspect
		tex_x = (1.0 - tex_w) * 0.5
		tex_y = 0.0
	} else {
		// Texture is taller - crop vertically
		tex_w = 1.0
		tex_h = texture_aspect / target_aspect
		tex_x = 0.0
		tex_y = (1.0 - tex_h) * 0.5
	}

	calc_tex_coord :: proc(
		px, py, rect_x, rect_y, rect_w, rect_h, tex_x, tex_y, tex_w, tex_h: f32,
	) -> [2]f32 {
		u := (px - rect_x) / rect_w
		v := (py - rect_y) / rect_h
		// Map to cropped texture coordinates
		u = tex_x + u * tex_w
		v = tex_y + v * tex_h
		return {u, v}
	}

	corners := [4][2]f32 {
		{x + clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + h - clamped_radius},
		{x + clamped_radius, y + h - clamped_radius},
	}

	corner_angles := [4][2]f32 {
		{math.PI, 3.0 * math.PI / 2.0},
		{3.0 * math.PI / 2.0, 2.0 * math.PI},
		{0.0, math.PI / 2.0},
		{math.PI / 2.0, math.PI},
	}

	// Draw rounded corners
	for corner_idx in 0 ..< 4 {
		corner_center := corners[corner_idx]
		start_angle := corner_angles[corner_idx][0]
		end_angle := corner_angles[corner_idx][1]

		angle_step := (end_angle - start_angle) / f32(corner_segments)

		center_tex := calc_tex_coord(
			corner_center.x,
			corner_center.y,
			x,
			y,
			w,
			h,
			tex_x,
			tex_y,
			tex_w,
			tex_h,
		)

		for i in 0 ..< corner_segments {
			angle1 := start_angle + f32(i) * angle_step
			angle2 := start_angle + f32(i + 1) * angle_step

			x1 := corner_center.x + clamped_radius * math.cos(angle1)
			y1 := corner_center.y + clamped_radius * math.sin(angle1)
			x2 := corner_center.x + clamped_radius * math.cos(angle2)
			y2 := corner_center.y + clamped_radius * math.sin(angle2)

			tex1 := calc_tex_coord(x1, y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h)
			tex2 := calc_tex_coord(x2, y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h)

			verts := []Vertex {
				Vertex{{corner_center.x, corner_center.y}, center_tex, color},
				Vertex{{x1, y1}, tex1, color},
				Vertex{{x2, y2}, tex2, color},
			}

			copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
			verticies_count += len(verts)
		}
	}

	// Draw center rectangle
	inner_w := w - 2.0 * clamped_radius
	inner_h := h - 2.0 * clamped_radius

	if inner_w > 0 && inner_h > 0 {
		center_x1 := x + clamped_radius
		center_y1 := y + clamped_radius
		center_x2 := x + w - clamped_radius
		center_y2 := y + h - clamped_radius

		center_verts := []Vertex {
			Vertex {
				{center_x1, center_y1},
				calc_tex_coord(center_x1, center_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{center_x1, center_y2},
				calc_tex_coord(center_x1, center_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{center_x2, center_y2},
				calc_tex_coord(center_x2, center_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{center_x1, center_y1},
				calc_tex_coord(center_x1, center_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{center_x2, center_y2},
				calc_tex_coord(center_x2, center_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{center_x2, center_y1},
				calc_tex_coord(center_x2, center_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
		}

		copy(verticies[verticies_count:verticies_count + len(center_verts)], center_verts[:])
		verticies_count += len(center_verts)
	}

	// Draw top and bottom rectangles
	if inner_w > 0 {
		// Top rectangle
		top_x1 := x + clamped_radius
		top_y1 := y
		top_x2 := x + w - clamped_radius
		top_y2 := y + clamped_radius

		top_verts := []Vertex {
			Vertex {
				{top_x1, top_y1},
				calc_tex_coord(top_x1, top_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{top_x1, top_y2},
				calc_tex_coord(top_x1, top_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{top_x2, top_y2},
				calc_tex_coord(top_x2, top_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{top_x1, top_y1},
				calc_tex_coord(top_x1, top_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{top_x2, top_y2},
				calc_tex_coord(top_x2, top_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{top_x2, top_y1},
				calc_tex_coord(top_x2, top_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
		}

		copy(verticies[verticies_count:verticies_count + len(top_verts)], top_verts[:])
		verticies_count += len(top_verts)

		// Bottom rectangle
		bottom_x1 := x + clamped_radius
		bottom_y1 := y + h - clamped_radius
		bottom_x2 := x + w - clamped_radius
		bottom_y2 := y + h

		bottom_verts := []Vertex {
			Vertex {
				{bottom_x1, bottom_y1},
				calc_tex_coord(bottom_x1, bottom_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{bottom_x1, bottom_y2},
				calc_tex_coord(bottom_x1, bottom_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{bottom_x2, bottom_y2},
				calc_tex_coord(bottom_x2, bottom_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{bottom_x1, bottom_y1},
				calc_tex_coord(bottom_x1, bottom_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{bottom_x2, bottom_y2},
				calc_tex_coord(bottom_x2, bottom_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{bottom_x2, bottom_y1},
				calc_tex_coord(bottom_x2, bottom_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
		}

		copy(verticies[verticies_count:verticies_count + len(bottom_verts)], bottom_verts[:])
		verticies_count += len(bottom_verts)
	}

	// Draw left and right rectangles
	if inner_h > 0 {
		// Left rectangle
		left_x1 := x
		left_y1 := y + clamped_radius
		left_x2 := x + clamped_radius
		left_y2 := y + h - clamped_radius

		left_verts := []Vertex {
			Vertex {
				{left_x1, left_y1},
				calc_tex_coord(left_x1, left_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{left_x1, left_y2},
				calc_tex_coord(left_x1, left_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{left_x2, left_y2},
				calc_tex_coord(left_x2, left_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{left_x1, left_y1},
				calc_tex_coord(left_x1, left_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{left_x2, left_y2},
				calc_tex_coord(left_x2, left_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{left_x2, left_y1},
				calc_tex_coord(left_x2, left_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
		}

		copy(verticies[verticies_count:verticies_count + len(left_verts)], left_verts[:])
		verticies_count += len(left_verts)

		// Right rectangle
		right_x1 := x + w - clamped_radius
		right_y1 := y + clamped_radius
		right_x2 := x + w
		right_y2 := y + h - clamped_radius

		right_verts := []Vertex {
			Vertex {
				{right_x1, right_y1},
				calc_tex_coord(right_x1, right_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{right_x1, right_y2},
				calc_tex_coord(right_x1, right_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{right_x2, right_y2},
				calc_tex_coord(right_x2, right_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{right_x1, right_y1},
				calc_tex_coord(right_x1, right_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{right_x2, right_y2},
				calc_tex_coord(right_x2, right_y2, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
			Vertex {
				{right_x2, right_y1},
				calc_tex_coord(right_x2, right_y1, x, y, w, h, tex_x, tex_y, tex_w, tex_h),
				color,
			},
		}

		copy(verticies[verticies_count:verticies_count + len(right_verts)], right_verts[:])
		verticies_count += len(right_verts)
	}
}

color_lerp :: proc(a, b: Color, t: f32) -> Color {
	return Color {
		r = u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t),
		g = u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
		b = u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t),
		a = u8(f32(a.a) + (f32(b.a) - f32(a.a)) * t),
	}
}

draw_gradient_rect_horizontal :: proc(x, y, w, h: f32, color_left, color_right: Color) {
	if ctx.is_minimized do return

	verts := []Vertex {
		Vertex{{x, y}, {-1.0, 0.0}, color_left},
		Vertex{{x, y + h}, {-1.0, 0.0}, color_left},
		Vertex{{x + w, y + h}, {-1.0, 0.0}, color_right},
		Vertex{{x, y}, {-1.0, 0.0}, color_left},
		Vertex{{x + w, y + h}, {-1.0, 0.0}, color_right},
		Vertex{{x + w, y}, {-1.0, 0.0}, color_right},
	}

	copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
	verticies_count += len(verts)
}


draw_gradient_rect_vertical :: proc(x, y, w, h: f32, color_top, color_bottom: Color) {
	if ctx.is_minimized do return

	verts := []Vertex {
		Vertex{{x, y}, {-1.0, 0.0}, color_top},
		Vertex{{x, y + h}, {-1.0, 0.0}, color_bottom},
		Vertex{{x + w, y + h}, {-1.0, 0.0}, color_bottom},
		Vertex{{x, y}, {-1.0, 0.0}, color_top},
		Vertex{{x + w, y + h}, {-1.0, 0.0}, color_bottom},
		Vertex{{x + w, y}, {-1.0, 0.0}, color_top},
	}

	copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
	verticies_count += len(verts)
}


draw_gradient_rect_diagonal :: proc(
	x, y, w, h: f32,
	color_tl, color_tr, color_bl, color_br: Color,
) {
	if ctx.is_minimized do return

	verts := []Vertex {
		Vertex{{x, y}, {-1.0, 0.0}, color_tl},
		Vertex{{x, y + h}, {-1.0, 0.0}, color_bl},
		Vertex{{x + w, y + h}, {-1.0, 0.0}, color_br},
		Vertex{{x, y}, {-1.0, 0.0}, color_tl},
		Vertex{{x + w, y + h}, {-1.0, 0.0}, color_br},
		Vertex{{x + w, y}, {-1.0, 0.0}, color_tr},
	}

	copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
	verticies_count += len(verts)
}

draw_gradient_circle_radial :: proc(
	center_x, center_y, radius: f32,
	color_center, color_edge: Color,
	segments: int = 32,
) {
	if ctx.is_minimized do return

	center := Vertex{{center_x, center_y}, {-1.0, 0.0}, color_center}
	angle_step := 2.0 * math.PI / f32(segments)

	for i in 0 ..< segments {
		angle1 := f32(i) * angle_step
		angle2 := f32((i + 1) % segments) * angle_step

		x1 := center_x + radius * math.cos(angle1)
		y1 := center_y + radius * math.sin(angle1)
		x2 := center_x + radius * math.cos(angle2)
		y2 := center_y + radius * math.sin(angle2)

		verts := []Vertex {
			center,
			Vertex{{x1, y1}, {-1.0, 0.0}, color_edge},
			Vertex{{x2, y2}, {-1.0, 0.0}, color_edge},
		}

		copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
		verticies_count += len(verts)
	}
}

draw_gradient_rect_multistop_horizontal :: proc(x, y, w, h: f32, colors: []Color, stops: []f32) {
	if ctx.is_minimized do return
	if len(colors) != len(stops) || len(colors) < 2 do return

	segments := len(colors) - 1
	for i in 0 ..< segments {
		segment_start := stops[i] * w
		segment_end := stops[i + 1] * w
		segment_width := segment_end - segment_start

		if segment_width > 0 {
			segment_x := x + segment_start

			verts := []Vertex {
				Vertex{{segment_x, y}, {-1.0, 0.0}, colors[i]},
				Vertex{{segment_x, y + h}, {-1.0, 0.0}, colors[i]},
				Vertex{{segment_x + segment_width, y + h}, {-1.0, 0.0}, colors[i + 1]},
				Vertex{{segment_x, y}, {-1.0, 0.0}, colors[i]},
				Vertex{{segment_x + segment_width, y + h}, {-1.0, 0.0}, colors[i + 1]},
				Vertex{{segment_x + segment_width, y}, {-1.0, 0.0}, colors[i + 1]},
			}

			copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
			verticies_count += len(verts)
		}
	}
}

draw_gradient_rect_multistop_vertical :: proc(x, y, w, h: f32, colors: []Color, stops: []f32) {
	if ctx.is_minimized do return
	if len(colors) != len(stops) || len(colors) < 2 do return

	segments := len(colors) - 1
	for i in 0 ..< segments {
		segment_start := stops[i] * h
		segment_end := stops[i + 1] * h
		segment_height := segment_end - segment_start

		if segment_height > 0 {
			segment_y := y + segment_start

			verts := []Vertex {
				Vertex{{x, segment_y}, {-1.0, 0.0}, colors[i]},
				Vertex{{x + w, segment_y}, {-1.0, 0.0}, colors[i]},
				Vertex{{x + w, segment_y + segment_height}, {-1.0, 0.0}, colors[i + 1]},
				Vertex{{x, segment_y}, {-1.0, 0.0}, colors[i]},
				Vertex{{x + w, segment_y + segment_height}, {-1.0, 0.0}, colors[i + 1]},
				Vertex{{x, segment_y + segment_height}, {-1.0, 0.0}, colors[i + 1]},
			}

			copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
			verticies_count += len(verts)
		}
	}
}

draw_gradient_rect_rounded_horizontal :: proc(
	x, y, w, h, radius: f32,
	color_left, color_right: Color,
	corner_segments: int = 8,
) {
	if ctx.is_minimized do return

	max_radius := min(w, h) * 0.5
	clamped_radius := min(radius, max_radius)

	if clamped_radius <= 0 {
		draw_gradient_rect_horizontal(x, y, w, h, color_left, color_right)
		return
	}


	interpolate_color_x :: proc(px, rect_x, rect_w: f32, color_left, color_right: Color) -> Color {
		t := (px - rect_x) / rect_w
		return color_lerp(color_left, color_right, t)
	}


	corners := [4][2]f32 {
		{x + clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + h - clamped_radius},
		{x + clamped_radius, y + h - clamped_radius},
	}


	corner_angles := [4][2]f32 {
		{math.PI, 3.0 * math.PI / 2.0},
		{3.0 * math.PI / 2.0, 2.0 * math.PI},
		{0.0, math.PI / 2.0},
		{math.PI / 2.0, math.PI},
	}


	for corner_idx in 0 ..< 4 {
		corner_center := corners[corner_idx]
		start_angle := corner_angles[corner_idx][0]
		end_angle := corner_angles[corner_idx][1]

		angle_step := (end_angle - start_angle) / f32(corner_segments)
		center_color := interpolate_color_x(corner_center.x, x, w, color_left, color_right)

		for i in 0 ..< corner_segments {
			angle1 := start_angle + f32(i) * angle_step
			angle2 := start_angle + f32(i + 1) * angle_step

			x1 := corner_center.x + clamped_radius * math.cos(angle1)
			y1 := corner_center.y + clamped_radius * math.sin(angle1)
			x2 := corner_center.x + clamped_radius * math.cos(angle2)
			y2 := corner_center.y + clamped_radius * math.sin(angle2)

			color1 := interpolate_color_x(x1, x, w, color_left, color_right)
			color2 := interpolate_color_x(x2, x, w, color_left, color_right)

			verts := []Vertex {
				Vertex{{corner_center.x, corner_center.y}, {-1.0, 0.0}, center_color},
				Vertex{{x1, y1}, {-1.0, 0.0}, color1},
				Vertex{{x2, y2}, {-1.0, 0.0}, color2},
			}

			copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
			verticies_count += len(verts)
		}
	}


	inner_w := w - 2.0 * clamped_radius
	inner_h := h - 2.0 * clamped_radius


	if inner_w > 0 && inner_h > 0 {
		center_x1 := x + clamped_radius
		center_y1 := y + clamped_radius
		center_x2 := x + w - clamped_radius
		center_y2 := y + h - clamped_radius

		color1 := interpolate_color_x(center_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(center_x2, x, w, color_left, color_right)

		center_verts := []Vertex {
			Vertex{{center_x1, center_y1}, {-1.0, 0.0}, color1},
			Vertex{{center_x1, center_y2}, {-1.0, 0.0}, color1},
			Vertex{{center_x2, center_y2}, {-1.0, 0.0}, color2},
			Vertex{{center_x1, center_y1}, {-1.0, 0.0}, color1},
			Vertex{{center_x2, center_y2}, {-1.0, 0.0}, color2},
			Vertex{{center_x2, center_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(center_verts)], center_verts[:])
		verticies_count += len(center_verts)
	}


	if inner_w > 0 {

		top_x1 := x + clamped_radius
		top_y1 := y
		top_x2 := x + w - clamped_radius
		top_y2 := y + clamped_radius

		color1 := interpolate_color_x(top_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(top_x2, x, w, color_left, color_right)

		top_verts := []Vertex {
			Vertex{{top_x1, top_y1}, {-1.0, 0.0}, color1},
			Vertex{{top_x1, top_y2}, {-1.0, 0.0}, color1},
			Vertex{{top_x2, top_y2}, {-1.0, 0.0}, color2},
			Vertex{{top_x1, top_y1}, {-1.0, 0.0}, color1},
			Vertex{{top_x2, top_y2}, {-1.0, 0.0}, color2},
			Vertex{{top_x2, top_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(top_verts)], top_verts[:])
		verticies_count += len(top_verts)


		bottom_x1 := x + clamped_radius
		bottom_y1 := y + h - clamped_radius
		bottom_x2 := x + w - clamped_radius
		bottom_y2 := y + h

		color1 = interpolate_color_x(bottom_x1, x, w, color_left, color_right)
		color2 = interpolate_color_x(bottom_x2, x, w, color_left, color_right)

		bottom_verts := []Vertex {
			Vertex{{bottom_x1, bottom_y1}, {-1.0, 0.0}, color1},
			Vertex{{bottom_x1, bottom_y2}, {-1.0, 0.0}, color1},
			Vertex{{bottom_x2, bottom_y2}, {-1.0, 0.0}, color2},
			Vertex{{bottom_x1, bottom_y1}, {-1.0, 0.0}, color1},
			Vertex{{bottom_x2, bottom_y2}, {-1.0, 0.0}, color2},
			Vertex{{bottom_x2, bottom_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(bottom_verts)], bottom_verts[:])
		verticies_count += len(bottom_verts)
	}


	if inner_h > 0 {

		left_x1 := x
		left_y1 := y + clamped_radius
		left_x2 := x + clamped_radius
		left_y2 := y + h - clamped_radius

		color1 := interpolate_color_x(left_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(left_x2, x, w, color_left, color_right)

		left_verts := []Vertex {
			Vertex{{left_x1, left_y1}, {-1.0, 0.0}, color1},
			Vertex{{left_x1, left_y2}, {-1.0, 0.0}, color1},
			Vertex{{left_x2, left_y2}, {-1.0, 0.0}, color2},
			Vertex{{left_x1, left_y1}, {-1.0, 0.0}, color1},
			Vertex{{left_x2, left_y2}, {-1.0, 0.0}, color2},
			Vertex{{left_x2, left_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(left_verts)], left_verts[:])
		verticies_count += len(left_verts)


		right_x1 := x + w - clamped_radius
		right_y1 := y + clamped_radius
		right_x2 := x + w
		right_y2 := y + h - clamped_radius

		color1 = interpolate_color_x(right_x1, x, w, color_left, color_right)
		color2 = interpolate_color_x(right_x2, x, w, color_left, color_right)

		right_verts := []Vertex {
			Vertex{{right_x1, right_y1}, {-1.0, 0.0}, color1},
			Vertex{{right_x1, right_y2}, {-1.0, 0.0}, color1},
			Vertex{{right_x2, right_y2}, {-1.0, 0.0}, color2},
			Vertex{{right_x1, right_y1}, {-1.0, 0.0}, color1},
			Vertex{{right_x2, right_y2}, {-1.0, 0.0}, color2},
			Vertex{{right_x2, right_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(right_verts)], right_verts[:])
		verticies_count += len(right_verts)
	}
}
draw_gradient_rect_rounded_vertical :: proc(
	x, y, w, h, radius: f32,
	color_top, color_bottom: Color,
	corner_segments: int = 8,
) {
	if ctx.is_minimized do return

	max_radius := min(w, h) * 0.5
	clamped_radius := min(radius, max_radius)

	if clamped_radius <= 0 {
		draw_gradient_rect_vertical(x, y, w, h, color_top, color_bottom)
		return
	}


	interpolate_color_y :: proc(py, rect_y, rect_h: f32, color_top, color_bottom: Color) -> Color {
		t := clamp((py - rect_y) / rect_h, 0.0, 1.0)
		return color_lerp(color_top, color_bottom, t)
	}


	corners := [4][2]f32 {
		{x + clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + clamped_radius},
		{x + w - clamped_radius, y + h - clamped_radius},
		{x + clamped_radius, y + h - clamped_radius},
	}


	corner_angles := [4][2]f32 {
		{math.PI, 3.0 * math.PI / 2.0},
		{3.0 * math.PI / 2.0, 2.0 * math.PI},
		{0.0, math.PI / 2.0},
		{math.PI / 2.0, math.PI},
	}


	for corner_idx in 0 ..< 4 {
		corner_center := corners[corner_idx]
		start_angle := corner_angles[corner_idx][0]
		end_angle := corner_angles[corner_idx][1]

		angle_step := (end_angle - start_angle) / f32(corner_segments)


		for i in 0 ..< corner_segments {
			angle1 := start_angle + f32(i) * angle_step
			angle2 := start_angle + f32(i + 1) * angle_step

			x1 := corner_center.x + clamped_radius * math.cos(angle1)
			y1 := corner_center.y + clamped_radius * math.sin(angle1)
			x2 := corner_center.x + clamped_radius * math.cos(angle2)
			y2 := corner_center.y + clamped_radius * math.sin(angle2)

			center_color := interpolate_color_y(corner_center.y, y, h, color_top, color_bottom)
			color1 := interpolate_color_y(y1, y, h, color_top, color_bottom)
			color2 := interpolate_color_y(y2, y, h, color_top, color_bottom)

			verts := []Vertex {
				Vertex{{corner_center.x, corner_center.y}, {-1.0, 0.0}, center_color},
				Vertex{{x1, y1}, {-1.0, 0.0}, color1},
				Vertex{{x2, y2}, {-1.0, 0.0}, color2},
			}

			copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
			verticies_count += len(verts)
		}
	}


	inner_w := w - 2.0 * clamped_radius
	inner_h := h - 2.0 * clamped_radius


	if inner_w > 0 && inner_h > 0 {
		center_x1 := x + clamped_radius
		center_y1 := y + clamped_radius
		center_x2 := x + w - clamped_radius
		center_y2 := y + h - clamped_radius

		color1 := interpolate_color_y(center_y1, y, h, color_top, color_bottom)
		color2 := interpolate_color_y(center_y2, y, h, color_top, color_bottom)

		center_verts := []Vertex {
			Vertex{{center_x1, center_y1}, {-1.0, 0.0}, color1},
			Vertex{{center_x1, center_y2}, {-1.0, 0.0}, color2},
			Vertex{{center_x2, center_y2}, {-1.0, 0.0}, color2},
			Vertex{{center_x1, center_y1}, {-1.0, 0.0}, color1},
			Vertex{{center_x2, center_y2}, {-1.0, 0.0}, color2},
			Vertex{{center_x2, center_y1}, {-1.0, 0.0}, color1},
		}

		copy(verticies[verticies_count:verticies_count + len(center_verts)], center_verts[:])
		verticies_count += len(center_verts)
	}


	if inner_w > 0 {

		top_x1 := x + clamped_radius
		top_y1 := y
		top_x2 := x + w - clamped_radius
		top_y2 := y + clamped_radius

		color1 := interpolate_color_y(top_y1, y, h, color_top, color_bottom)
		color2 := interpolate_color_y(top_y2, y, h, color_top, color_bottom)

		top_verts := []Vertex {
			Vertex{{top_x1, top_y1}, {-1.0, 0.0}, color1},
			Vertex{{top_x1, top_y2}, {-1.0, 0.0}, color2},
			Vertex{{top_x2, top_y2}, {-1.0, 0.0}, color2},
			Vertex{{top_x1, top_y1}, {-1.0, 0.0}, color1},
			Vertex{{top_x2, top_y2}, {-1.0, 0.0}, color2},
			Vertex{{top_x2, top_y1}, {-1.0, 0.0}, color1},
		}

		copy(verticies[verticies_count:verticies_count + len(top_verts)], top_verts[:])
		verticies_count += len(top_verts)


		bottom_x1 := x + clamped_radius
		bottom_y1 := y + h - clamped_radius
		bottom_x2 := x + w - clamped_radius
		bottom_y2 := y + h

		color1 = interpolate_color_y(bottom_y1, y, h, color_top, color_bottom)
		color2 = interpolate_color_y(bottom_y2, y, h, color_top, color_bottom)

		bottom_verts := []Vertex {
			Vertex{{bottom_x1, bottom_y1}, {-1.0, 0.0}, color1},
			Vertex{{bottom_x1, bottom_y2}, {-1.0, 0.0}, color2},
			Vertex{{bottom_x2, bottom_y2}, {-1.0, 0.0}, color2},
			Vertex{{bottom_x1, bottom_y1}, {-1.0, 0.0}, color1},
			Vertex{{bottom_x2, bottom_y2}, {-1.0, 0.0}, color2},
			Vertex{{bottom_x2, bottom_y1}, {-1.0, 0.0}, color1},
		}

		copy(verticies[verticies_count:verticies_count + len(bottom_verts)], bottom_verts[:])
		verticies_count += len(bottom_verts)
	}


	if inner_h > 0 {

		left_x1 := x
		left_y1 := y + clamped_radius
		left_x2 := x + clamped_radius
		left_y2 := y + h - clamped_radius

		color1 := interpolate_color_y(left_y1, y, h, color_top, color_bottom)
		color2 := interpolate_color_y(left_y2, y, h, color_top, color_bottom)

		left_verts := []Vertex {
			Vertex{{left_x1, left_y1}, {-1.0, 0.0}, color1},
			Vertex{{left_x1, left_y2}, {-1.0, 0.0}, color2},
			Vertex{{left_x2, left_y2}, {-1.0, 0.0}, color2},
			Vertex{{left_x1, left_y1}, {-1.0, 0.0}, color1},
			Vertex{{left_x2, left_y2}, {-1.0, 0.0}, color2},
			Vertex{{left_x2, left_y1}, {-1.0, 0.0}, color1},
		}

		copy(verticies[verticies_count:verticies_count + len(left_verts)], left_verts[:])
		verticies_count += len(left_verts)


		right_x1 := x + w - clamped_radius
		right_y1 := y + clamped_radius
		right_x2 := x + w
		right_y2 := y + h - clamped_radius

		color1 = interpolate_color_y(right_y1, y, h, color_top, color_bottom)
		color2 = interpolate_color_y(right_y2, y, h, color_top, color_bottom)

		right_verts := []Vertex {
			Vertex{{right_x1, right_y1}, {-1.0, 0.0}, color1},
			Vertex{{right_x1, right_y2}, {-1.0, 0.0}, color2},
			Vertex{{right_x2, right_y2}, {-1.0, 0.0}, color2},
			Vertex{{right_x1, right_y1}, {-1.0, 0.0}, color1},
			Vertex{{right_x2, right_y2}, {-1.0, 0.0}, color2},
			Vertex{{right_x2, right_y1}, {-1.0, 0.0}, color1},
		}

		copy(verticies[verticies_count:verticies_count + len(right_verts)], right_verts[:])
		verticies_count += len(right_verts)
	}
}


Corner_Flags :: enum u8 {
	TOP_LEFT     = 0,
	TOP_RIGHT    = 1,
	BOTTOM_RIGHT = 2,
	BOTTOM_LEFT  = 3,
}

Corner_Flag_Set :: bit_set[Corner_Flags;u8]


CORNER_ALL :: Corner_Flag_Set{.TOP_LEFT, .TOP_RIGHT, .BOTTOM_RIGHT, .BOTTOM_LEFT}
CORNER_TOP :: Corner_Flag_Set{.TOP_LEFT, .TOP_RIGHT}
CORNER_BOTTOM :: Corner_Flag_Set{.BOTTOM_LEFT, .BOTTOM_RIGHT}
CORNER_LEFT :: Corner_Flag_Set{.TOP_LEFT, .BOTTOM_LEFT}
CORNER_RIGHT :: Corner_Flag_Set{.TOP_RIGHT, .BOTTOM_RIGHT}

draw_gradient_rect_rounded_horizontal_selective :: proc(
	x, y, w, h, radius: f32,
	color_left, color_right: Color,
	corners: Corner_Flag_Set = CORNER_ALL,
	corner_segments: int = 8,
) {
	if ctx.is_minimized do return

	max_radius := min(w, h) * 0.5
	clamped_radius := min(radius, max_radius)

	if clamped_radius <= 0 || corners == {} {
		draw_gradient_rect_horizontal(x, y, w, h, color_left, color_right)
		return
	}


	interpolate_color_x :: proc(px, rect_x, rect_w: f32, color_left, color_right: Color) -> Color {
		t := (px - rect_x) / rect_w
		return color_lerp(color_left, color_right, t)
	}


	corner_info := [4]struct {
		center: [2]f32,
		angles: [2]f32,
		flag:   Corner_Flags,
	} {
		{{x + clamped_radius, y + clamped_radius}, {math.PI, 3.0 * math.PI / 2.0}, .TOP_LEFT},
		{
			{x + w - clamped_radius, y + clamped_radius},
			{3.0 * math.PI / 2.0, 2.0 * math.PI},
			.TOP_RIGHT,
		},
		{{x + w - clamped_radius, y + h - clamped_radius}, {0.0, math.PI / 2.0}, .BOTTOM_RIGHT},
		{{x + clamped_radius, y + h - clamped_radius}, {math.PI / 2.0, math.PI}, .BOTTOM_LEFT},
	}


	for info in corner_info {
		if info.flag not_in corners do continue

		corner_center := info.center
		start_angle := info.angles[0]
		end_angle := info.angles[1]

		angle_step := (end_angle - start_angle) / f32(corner_segments)
		center_color := interpolate_color_x(corner_center.x, x, w, color_left, color_right)

		for i in 0 ..< corner_segments {
			angle1 := start_angle + f32(i) * angle_step
			angle2 := start_angle + f32(i + 1) * angle_step

			x1 := corner_center.x + clamped_radius * math.cos(angle1)
			y1 := corner_center.y + clamped_radius * math.sin(angle1)
			x2 := corner_center.x + clamped_radius * math.cos(angle2)
			y2 := corner_center.y + clamped_radius * math.sin(angle2)

			color1 := interpolate_color_x(x1, x, w, color_left, color_right)
			color2 := interpolate_color_x(x2, x, w, color_left, color_right)

			verts := []Vertex {
				Vertex{{corner_center.x, corner_center.y}, {-1.0, 0.0}, center_color},
				Vertex{{x1, y1}, {-1.0, 0.0}, color1},
				Vertex{{x2, y2}, {-1.0, 0.0}, color2},
			}

			copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
			verticies_count += len(verts)
		}
	}


	top_left_r := clamped_radius if .TOP_LEFT in corners else 0
	top_right_r := clamped_radius if .TOP_RIGHT in corners else 0
	bottom_right_r := clamped_radius if .BOTTOM_RIGHT in corners else 0
	bottom_left_r := clamped_radius if .BOTTOM_LEFT in corners else 0


	center_x1 := x + max(top_left_r, bottom_left_r)
	center_x2 := x + w - max(top_right_r, bottom_right_r)
	center_y1 := y + max(top_left_r, top_right_r)
	center_y2 := y + h - max(bottom_left_r, bottom_right_r)


	if center_x2 > center_x1 && center_y2 > center_y1 {
		color1 := interpolate_color_x(center_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(center_x2, x, w, color_left, color_right)

		center_verts := []Vertex {
			Vertex{{center_x1, center_y1}, {-1.0, 0.0}, color1},
			Vertex{{center_x1, center_y2}, {-1.0, 0.0}, color1},
			Vertex{{center_x2, center_y2}, {-1.0, 0.0}, color2},
			Vertex{{center_x1, center_y1}, {-1.0, 0.0}, color1},
			Vertex{{center_x2, center_y2}, {-1.0, 0.0}, color2},
			Vertex{{center_x2, center_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(center_verts)], center_verts[:])
		verticies_count += len(center_verts)
	}


	top_x1 := x + top_left_r
	top_x2 := x + w - top_right_r
	if top_x2 > top_x1 {
		top_y1 := y
		top_y2 := y + max(top_left_r, top_right_r)

		color1 := interpolate_color_x(top_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(top_x2, x, w, color_left, color_right)

		top_verts := []Vertex {
			Vertex{{top_x1, top_y1}, {-1.0, 0.0}, color1},
			Vertex{{top_x1, top_y2}, {-1.0, 0.0}, color1},
			Vertex{{top_x2, top_y2}, {-1.0, 0.0}, color2},
			Vertex{{top_x1, top_y1}, {-1.0, 0.0}, color1},
			Vertex{{top_x2, top_y2}, {-1.0, 0.0}, color2},
			Vertex{{top_x2, top_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(top_verts)], top_verts[:])
		verticies_count += len(top_verts)
	}


	bottom_x1 := x + bottom_left_r
	bottom_x2 := x + w - bottom_right_r
	if bottom_x2 > bottom_x1 {
		bottom_y1 := y + h - max(bottom_left_r, bottom_right_r)
		bottom_y2 := y + h

		color1 := interpolate_color_x(bottom_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(bottom_x2, x, w, color_left, color_right)

		bottom_verts := []Vertex {
			Vertex{{bottom_x1, bottom_y1}, {-1.0, 0.0}, color1},
			Vertex{{bottom_x1, bottom_y2}, {-1.0, 0.0}, color1},
			Vertex{{bottom_x2, bottom_y2}, {-1.0, 0.0}, color2},
			Vertex{{bottom_x1, bottom_y1}, {-1.0, 0.0}, color1},
			Vertex{{bottom_x2, bottom_y2}, {-1.0, 0.0}, color2},
			Vertex{{bottom_x2, bottom_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(bottom_verts)], bottom_verts[:])
		verticies_count += len(bottom_verts)
	}


	left_y1 := y + max(top_left_r, top_right_r)
	left_y2 := y + h - max(bottom_left_r, bottom_right_r)
	if left_y2 > left_y1 {
		left_x1 := x
		left_x2 := x + max(top_left_r, bottom_left_r)

		color1 := interpolate_color_x(left_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(left_x2, x, w, color_left, color_right)

		left_verts := []Vertex {
			Vertex{{left_x1, left_y1}, {-1.0, 0.0}, color1},
			Vertex{{left_x1, left_y2}, {-1.0, 0.0}, color1},
			Vertex{{left_x2, left_y2}, {-1.0, 0.0}, color2},
			Vertex{{left_x1, left_y1}, {-1.0, 0.0}, color1},
			Vertex{{left_x2, left_y2}, {-1.0, 0.0}, color2},
			Vertex{{left_x2, left_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(left_verts)], left_verts[:])
		verticies_count += len(left_verts)
	}


	right_y1 := y + max(top_left_r, top_right_r)
	right_y2 := y + h - max(bottom_left_r, bottom_right_r)
	if right_y2 > right_y1 {
		right_x1 := x + w - max(top_right_r, bottom_right_r)
		right_x2 := x + w

		color1 := interpolate_color_x(right_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(right_x2, x, w, color_left, color_right)

		right_verts := []Vertex {
			Vertex{{right_x1, right_y1}, {-1.0, 0.0}, color1},
			Vertex{{right_x1, right_y2}, {-1.0, 0.0}, color1},
			Vertex{{right_x2, right_y2}, {-1.0, 0.0}, color2},
			Vertex{{right_x1, right_y1}, {-1.0, 0.0}, color1},
			Vertex{{right_x2, right_y2}, {-1.0, 0.0}, color2},
			Vertex{{right_x2, right_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(right_verts)], right_verts[:])
		verticies_count += len(right_verts)
	}


	corner_fill_info := [4]struct {
		condition: bool,
		bounds:    [4]f32,
	} {
		{.TOP_LEFT not_in corners, {x, y, x + clamped_radius, y + clamped_radius}},
		{.TOP_RIGHT not_in corners, {x + w - clamped_radius, y, x + w, y + clamped_radius}},
		{
			.BOTTOM_RIGHT not_in corners,
			{x + w - clamped_radius, y + h - clamped_radius, x + w, y + h},
		},
		{.BOTTOM_LEFT not_in corners, {x, y + h - clamped_radius, x + clamped_radius, y + h}},
	}

	for fill in corner_fill_info {
		if !fill.condition do continue

		corner_x1, corner_y1, corner_x2, corner_y2 :=
			fill.bounds.x, fill.bounds.y, fill.bounds.z, fill.bounds.w

		color1 := interpolate_color_x(corner_x1, x, w, color_left, color_right)
		color2 := interpolate_color_x(corner_x2, x, w, color_left, color_right)

		corner_verts := []Vertex {
			Vertex{{corner_x1, corner_y1}, {-1.0, 0.0}, color1},
			Vertex{{corner_x1, corner_y2}, {-1.0, 0.0}, color1},
			Vertex{{corner_x2, corner_y2}, {-1.0, 0.0}, color2},
			Vertex{{corner_x1, corner_y1}, {-1.0, 0.0}, color1},
			Vertex{{corner_x2, corner_y2}, {-1.0, 0.0}, color2},
			Vertex{{corner_x2, corner_y1}, {-1.0, 0.0}, color2},
		}

		copy(verticies[verticies_count:verticies_count + len(corner_verts)], corner_verts[:])
		verticies_count += len(corner_verts)
	}
}

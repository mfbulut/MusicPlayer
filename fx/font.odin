package fx

import "core:strings"
import "core:strconv"
import "core:encoding/csv"

import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"

font_hlsl := #load("font.hlsl")

// .\msdf-atlas-gen.exe -font .\BrittiSansTrial-Semibold-BF6757bfd443a8a.otf -format png -imageout font.png -csv font.csv -size 128 -outerempadding 0.1 -pxrange 8 -yorigin top
font_csv : string = #load("font.csv")
font_png : []u8   = #load("font.png")
font_texture : Texture
font_shader: ^D3D11.IPixelShader

Character :: struct {
    advance: f32,
    left   : f32,
    bottom : f32,
    right  : f32,
    top    : f32,
    left_px   : f32,
    bottom_px : f32,
    right_px  : f32,
    top_px    : f32,
}

default_font : [256]Character

load_from_csv :: proc() {
    r: csv.Reader
    r.trim_leading_space  = true
    r.reuse_record        = true
    r.reuse_record_buffer = true
    defer csv.reader_destroy(&r)

    csv.reader_init_with_string(&r, font_csv)

    for r, i, err in csv.iterator_next(&r) {
        assert(err == nil)

        char := strconv.atoi(r[0])

        advance := f32(strconv.atof(r[1]))
        left    := f32(strconv.atof(r[2]))
        bottom  := f32(strconv.atof(r[3]))
        right   := f32(strconv.atof(r[4]))
        top     := f32(strconv.atof(r[5]))

        left_px    := f32(strconv.atof(r[6]))
        bottom_px  := f32(strconv.atof(r[7]))
        right_px   := f32(strconv.atof(r[8]))
        top_px     := f32(strconv.atof(r[9]))

        default_font[char] = Character{advance, left, bottom, right, top, left_px, bottom_px, right_px, top_px}
    }
}

init_font :: proc() {
    load_from_csv()
    font_texture = load_texture_from_bytes(font_png)

	ps_blob: ^D3D11.IBlob
	D3D.Compile(raw_data(font_hlsl), len(font_hlsl), "font.hlsl", nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, nil)
	assert(ps_blob != nil)

	device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &font_shader)
}

draw_char :: proc(char: u8, x, y, size: f32, color: Color) -> f32 {
    if int(char) >= len(default_font) do return 0

    ch := default_font[char]

    char_width  := (ch.right - ch.left) * size
    char_height := (ch.top - ch.bottom) * size

    pos_x := x + ch.left * size
    pos_y := y + ch.bottom * size + size

    u_left  := ch.left_px   / f32(font_texture.width)
    u_right := ch.right_px  / f32(font_texture.width)
    v_top   := ch.top_px    / f32(font_texture.height)
    v_bottom:= ch.bottom_px / f32(font_texture.height)

    verts := []Vertex{
        Vertex{{pos_x, pos_y}, {u_left, v_bottom}, color},
        Vertex{{pos_x, pos_y + char_height}, {u_left, v_top}, color},
        Vertex{{pos_x + char_width, pos_y + char_height}, {u_right, v_top}, color},
        Vertex{{pos_x, pos_y}, {u_left, v_bottom}, color},
        Vertex{{pos_x + char_width, pos_y + char_height}, {u_right, v_top}, color},
        Vertex{{pos_x + char_width, pos_y}, {u_right, v_bottom}, color}
    }

    copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
    verticies_count += len(verts)

    return ch.advance * size
}

draw_text :: proc(text: string, x, y, size: f32, color: Color) {
    if ctx.is_minimized do return

    if(verticies_count > 0) {
        end_render()
    }

    use_texture(font_texture)

    update_constant_buffer({size / 128.0 * 8})

	device_context->PSSetShader(font_shader, nil, 0)

    cursor_x := x

    y := y

    for char in text {
        ch := char

        if ch == '\n' {
            cursor_x = x
            y += size
            continue
        }

        if ch == ' ' {
            cursor_x += default_font[' '].advance * size
            continue
        }

        if ch < 32 || ch > 126 {
            ch = '?'
        }

        advance := draw_char(u8(ch), cursor_x, y, size, color)
        cursor_x += advance
    }

    end_render()

	device_context->PSSetShader(pixel_shader, nil, 0)
}

measure_text :: proc(text: string, size: f32) -> f32 {
    width: f32 = 0

    for char in text {
        if char == '\n' {
            break
        }

        if int(char) < len(default_font) {
            width += default_font[char].advance * size
        }
    }

    return width
}

TextAlign :: enum {
    LEFT,
    CENTER,
    RIGHT,
}

draw_text_aligned :: proc(text: string, x, y, size: f32, color: Color, align: TextAlign) {
    if ctx.is_minimized do return

    final_x := x

    switch align {
    case .CENTER:
        text_width := measure_text(text, size)
        final_x = x - text_width / 2
    case .RIGHT:
        text_width := measure_text(text, size)
        final_x = x - text_width
    case .LEFT:
    }

    draw_text(text, final_x, y, size, color)
}

draw_text_wrapped :: proc(text: string, x, y, max_width, size: f32, color: Color) {
    if ctx.is_minimized do return

    if(verticies_count > 0) {
        end_render()
    }

    use_texture(font_texture)

    update_constant_buffer({size / 128.0 * 8})

	device_context->PSSetShader(font_shader, nil, 0)
    device_context->PSSetConstantBuffers(0, 1, &constant_buffer)

    cursor_x := x
    cursor_y := y
    line_height := size

    words := strings.split(text, " ")
    defer delete(words)

    for word in words {
        word_width := measure_text(word, size)
        space_width := default_font[' '].advance * size

        if cursor_x + word_width > x + max_width && cursor_x > x {
            cursor_x = x
            cursor_y += line_height
        }

        for char in word {
            ch := char

            if ch < 32 || ch > 126 {
                ch = '?'
            }

            advance := draw_char(u8(ch), cursor_x, cursor_y, size, color)
            cursor_x += advance
        }

        cursor_x += space_width
    }

    end_render()

	device_context->PSSetShader(pixel_shader, nil, 0)
}
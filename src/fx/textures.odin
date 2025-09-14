package fx

import D3D11 "vendor:directx/d3d11"

import "core:fmt"
import "core:image"
import "core:image/png"
import "core:image/qoi"
import "core:image/jpeg"
import "core:math"
import "core:os/os2"
import "core:mem"

import stb "vendor:stb/image"

Texture :: struct {
	texture:      ^D3D11.ITexture2D,
	texture_view: ^D3D11.IShaderResourceView,
	width:        int,
	height:       int,
}

load_texture :: proc(filepath: string, generate_mipmaps := true) -> (Texture, bool) {
	image_data, err := os2.read_entire_file(filepath, context.allocator)

	if err != nil {
		return Texture{}, false
	}

	texture := load_texture_from_bytes(image_data, generate_mipmaps)
	delete(image_data)

	return texture, true
}

load_texture_from_image :: proc(img: ^image.Image, generate_mipmaps := true) -> Texture {
	tex := Texture{}
	tex.width = img.width
	tex.height = img.height

	mip_levels := u32(1)
	if generate_mipmaps {
		mip_levels = u32(math.floor(math.log2(f64(max(img.width, img.height)))) + 1)
	}

	bind_flags := D3D11.BIND_FLAGS{.SHADER_RESOURCE}
	if generate_mipmaps {
		bind_flags |= {.RENDER_TARGET}
	}

	texture_desc := D3D11.TEXTURE2D_DESC {
		Width = u32(img.width),
		Height = u32(img.height),
		MipLevels = mip_levels,
		ArraySize = 1,
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {Count = 1},
		Usage = .DEFAULT,
		BindFlags = bind_flags,
		MiscFlags = generate_mipmaps ? {.GENERATE_MIPS} : {},
	}

	texture: ^D3D11.ITexture2D
	if generate_mipmaps {
		device->CreateTexture2D(&texture_desc, nil, &texture)
		device_context->UpdateSubresource(
			texture,
			0,
			nil,
			&img.pixels.buf[0],
			u32(img.width) * 4,
			0,
		)
	} else {
		texture_data := D3D11.SUBRESOURCE_DATA {
			pSysMem     = &img.pixels.buf[0],
			SysMemPitch = u32(img.width) * 4,
		}
		device->CreateTexture2D(&texture_desc, &texture_data, &texture)
	}

	texture_view: ^D3D11.IShaderResourceView
	srv_desc := D3D11.SHADER_RESOURCE_VIEW_DESC {
		Format = texture_desc.Format,
		ViewDimension = .TEXTURE2D,
		Texture2D = {MipLevels = mip_levels},
	}
	device->CreateShaderResourceView(texture, &srv_desc, &texture_view)

	if generate_mipmaps {
		device_context->GenerateMips(texture_view)
	}

	tex.texture = texture
	tex.texture_view = texture_view

	return tex
}

SMALL_SIZE :: 64

load_texture_from_bytes :: proc(data: []u8, generate_mipmaps := true, downsample := false) -> Texture {
	img, err := image.load_from_bytes(data, {.alpha_add_if_missing})

	if err != nil {
		return Texture{}
	}

	if downsample && (img.width > SMALL_SIZE || img.height > SMALL_SIZE) {
		original_pixels := img.pixels.buf

		target_w, target_h: i32
		if img.width > img.height {
			target_w = SMALL_SIZE
			target_h = max(1, (i32(img.height) * SMALL_SIZE) / i32(img.width))
		} else {
			target_h = SMALL_SIZE
			target_w = max(1, (i32(img.width) * SMALL_SIZE) / i32(img.height))
		}

		resized_pixel_count := int(target_w * target_h)
		resized_pixels := make([][4]u8, resized_pixel_count)
		stb.resize_uint8(
			&original_pixels[0], i32(img.width), i32(img.height), 0,
			cast([^]u8)&resized_pixels[0], target_w, target_h, 0,
			4,
		)
		image.destroy(img)
		resized_img, ok := image.pixels_to_image(resized_pixels, int(target_w), int(target_h))
		if !ok {
			fmt.eprintfln("[ERROR] Failed to convert resized pixels to image")
			delete(resized_pixels)
			return Texture{}
		}
		texture := load_texture_from_image(&resized_img, generate_mipmaps)
		delete(resized_pixels)
		return texture
	} else {
		texture := load_texture_from_image(img, generate_mipmaps)
		image.destroy(img)
		return texture
	}
}

unload_texture :: proc(tex: ^Texture) {
	if tex.texture_view != nil {
		tex.texture_view->Release()
		tex.texture_view = nil
	}
	if tex.texture != nil {
		tex.texture->Release()
		tex.texture = nil
	}
	tex.width = 0
	tex.height = 0
}

use_texture :: proc(texture: Texture) {
	if (verticies_count > 0) {
		end_render()
	}
	texture_view := texture.texture_view
	device_context->PSSetShaderResources(0, 1, &texture_view)
}

package fx

import D3D11 "vendor:directx/d3d11"
import "core:os"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:image/qoi"
import "core:math"


import stb "vendor:stb/image"

Texture :: struct {
    texture: ^D3D11.ITexture2D,
    texture_view: ^D3D11.IShaderResourceView,
    width:  int,
    height: int,
}

load_texture :: proc(filepath: string, generate_mipmaps := true) -> (Texture, bool) {
    image_data, ok := os.read_entire_file(filepath)
    if ok {
        texture := load_texture_from_bytes(image_data, generate_mipmaps)
        delete(image_data)
        return texture, true
    }

    return Texture{}, false
}

load_texture_from_image :: proc(img: ^image.Image, generate_mipmaps := true) -> Texture {
    tex := Texture{}
    tex.width  = img.width
    tex.height = img.height

    mip_levels := u32(1)
    if generate_mipmaps {
        mip_levels = u32(math.floor(math.log2(f64(max(img.width, img.height)))) + 1)
    }

    bind_flags := D3D11.BIND_FLAGS{.SHADER_RESOURCE}
    if generate_mipmaps {
        bind_flags |= {.RENDER_TARGET}
    }

    texture_desc := D3D11.TEXTURE2D_DESC{
        Width      = u32(img.width),
        Height     = u32(img.height),
        MipLevels  = mip_levels,
        ArraySize  = 1,
        Format     = .R8G8B8A8_UNORM,
        SampleDesc = {Count = 1},
        Usage      = .DEFAULT,
        BindFlags  = bind_flags,
        MiscFlags  = generate_mipmaps ? {.GENERATE_MIPS} : {},
    }

    texture : ^D3D11.ITexture2D
    if generate_mipmaps {
        device->CreateTexture2D(&texture_desc, nil, &texture)
        device_context->UpdateSubresource(texture, 0, nil, &img.pixels.buf[0], u32(img.width) * 4, 0)
    } else {
        texture_data := D3D11.SUBRESOURCE_DATA{
            pSysMem     = &img.pixels.buf[0],
            SysMemPitch = u32(img.width) * 4,
        }
        device->CreateTexture2D(&texture_desc, &texture_data, &texture)
    }

    texture_view : ^D3D11.IShaderResourceView
    srv_desc := D3D11.SHADER_RESOURCE_VIEW_DESC{
        Format        = texture_desc.Format,
        ViewDimension = .TEXTURE2D,
        Texture2D     = {MipLevels = mip_levels},
    }
    device->CreateShaderResourceView(texture, &srv_desc, &texture_view)

    if generate_mipmaps {
        device_context->GenerateMips(texture_view)
    }

    tex.texture = texture
    tex.texture_view = texture_view

    return tex
}
load_texture_from_bytes :: proc(data: []u8, generate_mipmaps := true) -> Texture {
    img, err := image.load_from_bytes(data, {.alpha_add_if_missing})


    if err != nil {
        w, h, channels_in_file: i32
        pixels_ptr := stb.load_from_memory(&data[0], i32(len(data)), &w, &h, &channels_in_file, 4)

        if pixels_ptr == nil {
            fmt.printfln("[ERROR] Failed to load texture from bytes using both image and STB loaders")
            return Texture{}
        }

        pixel_count := int(w * h)
        rgba_pixels := make([][4]u8, pixel_count)

        for i in 0..<pixel_count {
            rgba_pixels[i] = {
                pixels_ptr[i * 4 + 0],
                pixels_ptr[i * 4 + 1],
                pixels_ptr[i * 4 + 2],
                pixels_ptr[i * 4 + 3],
            }
        }

        stb.image_free(pixels_ptr)

        fallback_img, ok := image.pixels_to_image(rgba_pixels, int(w), int(h))
        if !ok {
            fmt.printfln("[ERROR] Failed to convert STB pixels to image")
            return Texture{}
        }

        texture := load_texture_from_image(&fallback_img)
        delete(rgba_pixels)
        return texture
    } else {
        texture := load_texture_from_image(img)
        image.destroy(img)
        return texture
    }

    return Texture{}
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

use_texture :: proc(texture : Texture) {
    if(verticies_count > 0) {
        end_render()
    }
    texture_view := texture.texture_view
    device_context->PSSetShaderResources(0, 1, &texture_view)
}
package fx

import D3D11 "vendor:directx/d3d11"
import "core:fmt"

// Extended texture struct to support render targets
RenderTexture :: struct {
    using tx: Texture, // Inherit from base Texture
    render_target_view: ^D3D11.IRenderTargetView,
    depth_stencil: ^D3D11.ITexture2D,
    depth_stencil_view: ^D3D11.IDepthStencilView,
}

// Create render texture with specified dimensions
create_render_texture :: proc(width, height: int,
                             use_depth: bool = true) -> RenderTexture {
    rt := RenderTexture{}
    rt.width = width
    rt.height = height

    // Create the main texture (render target)
    texture_desc := D3D11.TEXTURE2D_DESC{
        Width      = u32(width),
        Height     = u32(height),
        MipLevels  = 1,
        ArraySize  = 1,
        Format     = .R8G8B8A8_UNORM,
        SampleDesc = {Count = 1, Quality = 0},
        Usage      = .DEFAULT,
        BindFlags  = {.RENDER_TARGET, .SHADER_RESOURCE},
        CPUAccessFlags = {},
        MiscFlags  = {},
    }

    hr := device->CreateTexture2D(&texture_desc, nil, &rt.texture)
    if hr != 0 {
        fmt.printfln("[ERROR] Failed to create render texture: %x", hr)
        return rt
    }

    // Create render target view
    device->CreateRenderTargetView(rt.texture, nil, &rt.render_target_view)

    // Create shader resource view for sampling the render texture
    srv_desc := D3D11.SHADER_RESOURCE_VIEW_DESC{
        Format        = .R8G8B8A8_UNORM,
        ViewDimension = .TEXTURE2D,
        Texture2D     = {MipLevels = 1},
    }
    device->CreateShaderResourceView(rt.texture, &srv_desc, &rt.texture_view)

    // Create depth stencil buffer if requested
    if use_depth {
        depth_desc := D3D11.TEXTURE2D_DESC{
            Width      = u32(width),
            Height     = u32(height),
            MipLevels  = 1,
            ArraySize  = 1,
            Format     = .D24_UNORM_S8_UINT,
            SampleDesc = {Count = 1, Quality = 0},
            Usage      = .DEFAULT,
            BindFlags  = {.DEPTH_STENCIL},
            CPUAccessFlags = {},
            MiscFlags  = {},
        }

        device->CreateTexture2D(&depth_desc, nil, &rt.depth_stencil)
        device->CreateDepthStencilView(rt.depth_stencil, nil, &rt.depth_stencil_view)
    }

    return rt
}

// Destroy render texture and free resources
destroy_render_texture :: proc(rt: ^RenderTexture) {
    if rt.render_target_view != nil {
        rt.render_target_view->Release()
        rt.render_target_view = nil
    }
    if rt.depth_stencil_view != nil {
        rt.depth_stencil_view->Release()
        rt.depth_stencil_view = nil
    }
    if rt.depth_stencil != nil {
        rt.depth_stencil->Release()
        rt.depth_stencil = nil
    }
    unload_texture(&rt.tx)
}

// Begin rendering to the render texture
begin_render_to_texture :: proc(rt: ^RenderTexture, clear_color: Color = {0, 0, 0, 255}) {
    // End any current rendering
    if verticies_count > 0 {
        end_render()
    }

    // Set viewport for render texture
    rt_viewport := D3D11.VIEWPORT{
        TopLeftX = 0,
        TopLeftY = 0,
        Width    = f32(rt.width),
        Height   = f32(rt.height),
        MinDepth = 0.0,
        MaxDepth = 1.0,
    }
    device_context->RSSetViewports(1, &rt_viewport)

    // Set render targets
    device_context->OMSetRenderTargets(1, &rt.render_target_view, rt.depth_stencil_view)

    // Clear render target
    clear_color_f := [4]f32{
        f32(clear_color.r) / 255.0,
        f32(clear_color.g) / 255.0,
        f32(clear_color.b) / 255.0,
        f32(clear_color.a) / 255.0,
    }
    device_context->ClearRenderTargetView(rt.render_target_view, &clear_color_f)

    // Clear depth stencil if it exists
    if rt.depth_stencil_view != nil {
        device_context->ClearDepthStencilView(rt.depth_stencil_view, {.DEPTH, .STENCIL}, 1.0, 0)
    }

    // Update constant buffer for render texture dimensions
    update_constant_buffer_for_rt(rt.width, rt.height)
}

// End rendering to render texture and restore main framebuffer
end_render_to_texture :: proc() {
    // End any pending rendering
    if verticies_count > 0 {
        end_render()
    }

    // Restore main framebuffer
    device_context->RSSetViewports(1, &viewport)
    device_context->OMSetRenderTargets(1, &msaa_render_target_view, msaa_depth_stencil_view)

    // Restore constant buffer for main window
    update_constant_buffer()
}

// Helper to update constant buffer for render texture dimensions
@(private)
update_constant_buffer_for_rt :: proc(width, height: int, data: []f32 = {}) {
    constants: [3]f32
    constants[0] = 2.0 / f32(width)
    constants[1] = -2.0 / f32(height)
    copy(constants[2:2+len(data)], data[:len(data)])

    mapped_subresource: D3D11.MAPPED_SUBRESOURCE
    device_context->Map(constant_buffer, 0, .WRITE_DISCARD, {}, &mapped_subresource)
    {
        constant_data := (^[16]f32)(mapped_subresource.pData)
        copy(constant_data[:], constants[:])
    }
    device_context->Unmap(constant_buffer, 0)
}

use_render_texture :: proc(rt: RenderTexture) {
    use_texture(rt.tx)
}

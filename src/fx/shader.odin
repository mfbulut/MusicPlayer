package fx

import "core:fmt"
import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"

Shader :: struct {
    fragment : ^D3D11.IPixelShader
}

load_shader :: proc(hlsl : []u8) -> Shader {
    shader := Shader{ fragment = nil }

    ps_blob: ^D3D11.IBlob
    ps_error_blob: ^D3D11.IBlob

    hr := D3D.Compile(raw_data(hlsl), len(hlsl), "shaders.hlsl", nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, &ps_error_blob)

    if hr != 0 {
        if ps_error_blob != nil {
            error_msg := cstring(ps_error_blob->GetBufferPointer())
            fmt.printf("Pixel shader compilation error:\n%s\n", error_msg)
            ps_error_blob->Release()
        }
        return shader
    }

    assert(ps_blob != nil)

    hr = device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &shader.fragment)

    ps_blob->Release()

    if hr != 0 {
        fmt.printf("CreatePixelShader failed with HRESULT: 0x%x\n", hr)
    }

    return shader
}

use_shader :: proc(shader: Shader) {
    if(verticies_count > 0) {
        end_render()
    }

    if shader.fragment == nil {
        device_context->PSSetShader(pixel_shader, nil, 0)
	    device_context->PSSetConstantBuffers(0, 1, &constant_buffer)
    } else {
        device_context->PSSetShader(shader.fragment, nil, 0)
	    device_context->PSSetConstantBuffers(0, 1, &constant_buffer)
    }
}
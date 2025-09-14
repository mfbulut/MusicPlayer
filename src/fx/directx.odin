package fx

import "core:fmt"

import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"
import DXGI "vendor:directx/dxgi"

shaders_hlsl: []u8 = #load("shader.hlsl")

device: ^D3D11.IDevice
device_context: ^D3D11.IDeviceContext
swapchain: ^DXGI.ISwapChain1
framebuffer_view: ^D3D11.IRenderTargetView

// MSAA resources
msaa_render_target: ^D3D11.ITexture2D
msaa_render_target_view: ^D3D11.IRenderTargetView
msaa_depth_stencil: ^D3D11.ITexture2D
msaa_depth_stencil_view: ^D3D11.IDepthStencilView

vertex_shader: ^D3D11.IVertexShader
input_layout: ^D3D11.IInputLayout
pixel_shader: ^D3D11.IPixelShader

rasterizer_state: ^D3D11.IRasterizerState
sampler_state: ^D3D11.ISamplerState
blend_state: ^D3D11.IBlendState
depth_stencil_state: ^D3D11.IDepthStencilState
constant_buffer: ^D3D11.IBuffer
vertex_buffer: ^D3D11.IBuffer

viewport: D3D11.VIEWPORT

vertex_buffer_stride: u32 = 5 * 4
vertex_buffer_offset: u32 = 0

MSAA_SAMPLE_COUNT :: 4
msaa_quality: u32

@(private)
init_dx :: proc() {
	feature_levels := [?]D3D11.FEATURE_LEVEL{._11_0}

	base_device: ^D3D11.IDevice
	base_device_context: ^D3D11.IDeviceContext

	D3D11.CreateDevice(
		nil,
		.HARDWARE,
		nil,
		{.BGRA_SUPPORT},
		&feature_levels[0],
		len(feature_levels),
		D3D11.SDK_VERSION,
		&base_device,
		nil,
		&base_device_context,
	)

	base_device->QueryInterface(D3D11.IDevice_UUID, (^rawptr)(&device))
	base_device_context->QueryInterface(D3D11.IDeviceContext_UUID, (^rawptr)(&device_context))

	device->CheckMultisampleQualityLevels(.B8G8R8A8_UNORM, MSAA_SAMPLE_COUNT, &msaa_quality)
	assert(msaa_quality > 0, "MSAA not supported with the specified sample count")
	msaa_quality -= 1

	dxgi_device: ^DXGI.IDevice
	device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device))

	dxgi_adapter: ^DXGI.IAdapter
	dxgi_device->GetAdapter(&dxgi_adapter)

	dxgi_factory: ^DXGI.IFactory2
	dxgi_adapter->GetParent(DXGI.IFactory2_UUID, (^rawptr)(&dxgi_factory))

	///////////////////////////////////////////////////////////////////////////////////////////////

	swapchain_desc := DXGI.SWAP_CHAIN_DESC1 {
		Width = 0,
		Height = 0,
		Format = .B8G8R8A8_UNORM,
		Stereo = false,
		SampleDesc = {Count = 1, Quality = 0},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		Scaling = .STRETCH,
		SwapEffect = .DISCARD,
		AlphaMode = .UNSPECIFIED,
		Flags = {},
	}

	dxgi_factory->CreateSwapChainForHwnd(device, ctx.hwnd, &swapchain_desc, nil, nil, &swapchain)

	create_framebuffer()

	///////////////////////////////////////////////////////////////////////////////////////////////

	vs_blob: ^D3D11.IBlob
	vs_error_blob: ^D3D11.IBlob
	hr := D3D.Compile(
		raw_data(shaders_hlsl),
		len(shaders_hlsl),
		"shaders.hlsl",
		nil,
		nil,
		"vs_main",
		"vs_5_0",
		0,
		0,
		&vs_blob,
		&vs_error_blob,
	)

	if hr != 0 {
		if vs_error_blob != nil {
			error_msg := cstring(vs_error_blob->GetBufferPointer())
			fmt.printf("Vertex shader compilation error:\n%s\n", error_msg)
			vs_error_blob->Release()
		}
	}

	assert(vs_blob != nil)

	device->CreateVertexShader(
		vs_blob->GetBufferPointer(),
		vs_blob->GetBufferSize(),
		nil,
		&vertex_shader,
	)

	input_element_desc := [?]D3D11.INPUT_ELEMENT_DESC {
		{"POS", 0, .R32G32_FLOAT, 0, 0, .VERTEX_DATA, 0},
		{"TEX", 0, .R32G32_FLOAT, 0, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0},
		{"COL", 0, .R8G8B8A8_UNORM, 0, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0},
	}

	device->CreateInputLayout(
		&input_element_desc[0],
		len(input_element_desc),
		vs_blob->GetBufferPointer(),
		vs_blob->GetBufferSize(),
		&input_layout,
	)

	ps_blob: ^D3D11.IBlob
	ps_error_blob: ^D3D11.IBlob
	hr = D3D.Compile(
		raw_data(shaders_hlsl),
		len(shaders_hlsl),
		"shaders.hlsl",
		nil,
		nil,
		"ps_main",
		"ps_5_0",
		0,
		0,
		&ps_blob,
		&ps_error_blob,
	)

	if hr != 0 {
		if ps_error_blob != nil {
			error_msg := cstring(ps_error_blob->GetBufferPointer())
			fmt.printf("Pixel shader compilation error:\n%s\n", error_msg)
			ps_error_blob->Release()
		}
		vs_blob->Release()
	}

	assert(ps_blob != nil)

	device->CreatePixelShader(
		ps_blob->GetBufferPointer(),
		ps_blob->GetBufferSize(),
		nil,
		&pixel_shader,
	)

	///////////////////////////////////////////////////////////////////////////////////////////////

	rasterizer_desc := D3D11.RASTERIZER_DESC {
		FillMode          = .SOLID,
		CullMode          = .NONE,
		ScissorEnable     = true,
		MultisampleEnable = true,
	}

	device->CreateRasterizerState(&rasterizer_desc, &rasterizer_state)

	sampler_desc := D3D11.SAMPLER_DESC {
		Filter         = .MIN_MAG_MIP_LINEAR,
		AddressU       = .WRAP,
		AddressV       = .WRAP,
		AddressW       = .WRAP,
		MipLODBias     = -0.5,
		MaxAnisotropy  = 1,
		ComparisonFunc = .NEVER,
		BorderColor    = {0, 0, 0, 0},
		MinLOD         = 0.0,
		MaxLOD         = 4.0,
	}

	device->CreateSamplerState(&sampler_desc, &sampler_state)

	blend_desc: D3D11.BLEND_DESC = {
		AlphaToCoverageEnable  = false,
		IndependentBlendEnable = false,
		RenderTarget           = [8]D3D11.RENDER_TARGET_BLEND_DESC {
			{
				BlendEnable = true,
				SrcBlend = D3D11.BLEND.ONE,
				DestBlend = D3D11.BLEND.INV_SRC_ALPHA,
				BlendOp = D3D11.BLEND_OP.ADD,
				SrcBlendAlpha = D3D11.BLEND.ONE,
				DestBlendAlpha = D3D11.BLEND.INV_SRC_ALPHA,
				BlendOpAlpha = D3D11.BLEND_OP.ADD,
				RenderTargetWriteMask = 15,
			},
			{},
			{},
			{},
			{},
			{},
			{},
			{},
		},
	}

	device->CreateBlendState(&blend_desc, &blend_state)

	depth_stencil_desc := D3D11.DEPTH_STENCIL_DESC {
		DepthEnable    = true,
		DepthWriteMask = .ZERO,
		DepthFunc      = .LESS,
		StencilEnable  = false,
	}

	device->CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state)

	///////////////////////////////////////////////////////////////////////////////////////////////

	vertex_buffer_desc := D3D11.BUFFER_DESC {
		ByteWidth      = MAX_VERTICIES * size_of(Vertex),
		Usage          = .DYNAMIC,
		BindFlags      = {.VERTEX_BUFFER},
		CPUAccessFlags = {.WRITE},
	}

	device->CreateBuffer(&vertex_buffer_desc, nil, &vertex_buffer)

	constant_buffer_desc := D3D11.BUFFER_DESC {
		ByteWidth      = 16,
		Usage          = .DYNAMIC,
		BindFlags      = {.CONSTANT_BUFFER},
		CPUAccessFlags = {.WRITE},
	}

	device->CreateBuffer(&constant_buffer_desc, nil, &constant_buffer)
}

@(private)
create_framebuffer :: proc() {
	if framebuffer_view != nil {
		framebuffer_view->Release()
		framebuffer_view = nil
	}
	if msaa_render_target_view != nil {
		msaa_render_target_view->Release()
		msaa_render_target_view = nil
	}
	if msaa_render_target != nil {
		msaa_render_target->Release()
		msaa_render_target = nil
	}
	if msaa_depth_stencil_view != nil {
		msaa_depth_stencil_view->Release()
		msaa_depth_stencil_view = nil
	}
	if msaa_depth_stencil != nil {
		msaa_depth_stencil->Release()
		msaa_depth_stencil = nil
	}

	framebuffer: ^D3D11.ITexture2D
	swapchain->GetBuffer(0, D3D11.ITexture2D_UUID, (^rawptr)(&framebuffer))
	device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)

	viewport_desc: D3D11.TEXTURE2D_DESC
	framebuffer->GetDesc(&viewport_desc)
	viewport = D3D11.VIEWPORT{0, 0, f32(viewport_desc.Width), f32(viewport_desc.Height), 0, 1}

	msaa_texture_desc := D3D11.TEXTURE2D_DESC {
		Width = viewport_desc.Width,
		Height = viewport_desc.Height,
		MipLevels = 1,
		ArraySize = 1,
		Format = .B8G8R8A8_UNORM,
		SampleDesc = {Count = MSAA_SAMPLE_COUNT, Quality = msaa_quality},
		Usage = .DEFAULT,
		BindFlags = {.RENDER_TARGET},
		CPUAccessFlags = {},
		MiscFlags = {},
	}

	device->CreateTexture2D(&msaa_texture_desc, nil, &msaa_render_target)
	device->CreateRenderTargetView(msaa_render_target, nil, &msaa_render_target_view)


	depth_texture_desc := D3D11.TEXTURE2D_DESC {
		Width = viewport_desc.Width,
		Height = viewport_desc.Height,
		MipLevels = 1,
		ArraySize = 1,
		Format = .D24_UNORM_S8_UINT,
		SampleDesc = {Count = MSAA_SAMPLE_COUNT, Quality = msaa_quality},
		Usage = .DEFAULT,
		BindFlags = {.DEPTH_STENCIL},
		CPUAccessFlags = {},
		MiscFlags = {},
	}

	device->CreateTexture2D(&depth_texture_desc, nil, &msaa_depth_stencil)
	device->CreateDepthStencilView(msaa_depth_stencil, nil, &msaa_depth_stencil_view)

	framebuffer->Release()
}

@(private)
update_constant_buffer :: proc(data: []f32 = {}) {
	width, height := window_size()
	constants: [16]f32
	constants[0] = 2.0 / f32(width)
	constants[1] = -2.0 / f32(height)
	constants[2] = ctx.timer

	copy(constants[3:3 + len(data)], data[:len(data)])

	mapped_subresource: D3D11.MAPPED_SUBRESOURCE
	device_context->Map(constant_buffer, 0, .WRITE_DISCARD, {}, &mapped_subresource)
	{
		constant_data := (^[16]f32)(mapped_subresource.pData)
		copy(constant_data[:], constants[:])
	}
	device_context->Unmap(constant_buffer, 0)
}

@(private)
resize_swapchain :: proc(width, height: int) {
	if swapchain == nil do return
	if width <= 0 || height <= 0 do return

	if msaa_render_target_view != nil {
		msaa_render_target_view->Release()
		msaa_render_target_view = nil
	}
	if msaa_render_target != nil {
		msaa_render_target->Release()
		msaa_render_target = nil
	}
	if msaa_depth_stencil_view != nil {
		msaa_depth_stencil_view->Release()
		msaa_depth_stencil_view = nil
	}
	if msaa_depth_stencil != nil {
		msaa_depth_stencil->Release()
		msaa_depth_stencil = nil
	}
	if framebuffer_view != nil {
		framebuffer_view->Release()
		framebuffer_view = nil
	}

	hr := swapchain->ResizeBuffers(0, u32(width), u32(height), .UNKNOWN, {})
	assert(hr >= 0, "Failed to resize swapchain")

	create_framebuffer()
	update_constant_buffer()
}

clear_background :: proc() {
	device_context->ClearRenderTargetView(
		msaa_render_target_view,
		&[4]f32 {
			0,
			0,
			0,
			0,
		},
	)
	device_context->ClearDepthStencilView(msaa_depth_stencil_view, {.DEPTH, .STENCIL}, 1.0, 0)
}

begin_render :: proc() {
	device_context->IASetPrimitiveTopology(.TRIANGLELIST)
	device_context->IASetInputLayout(input_layout)
	device_context->IASetVertexBuffers(
		0,
		1,
		&vertex_buffer,
		&vertex_buffer_stride,
		&vertex_buffer_offset,
	)

	device_context->VSSetShader(vertex_shader, nil, 0)
	device_context->VSSetConstantBuffers(0, 1, &constant_buffer)

	device_context->RSSetViewports(1, &viewport)
	device_context->RSSetState(rasterizer_state)

	device_context->PSSetShader(pixel_shader, nil, 0)
	device_context->PSSetConstantBuffers(0, 1, &constant_buffer)

	device_context->PSSetSamplers(0, 1, &sampler_state)
	device_context->OMSetDepthStencilState(depth_stencil_state, 0)
	device_context->OMSetBlendState(blend_state, nil, 0xffffffff)

	device_context->OMSetRenderTargets(1, &msaa_render_target_view, msaa_depth_stencil_view)
}

end_render :: proc() {
	mapped_subresource: D3D11.MAPPED_SUBRESOURCE
	device_context->Map(vertex_buffer, 0, .WRITE_DISCARD, {}, &mapped_subresource)
	{
		verticies_buf := (^[MAX_VERTICIES]Vertex)(mapped_subresource.pData)

		for i in 0 ..< verticies_count {
			verticies_buf[i] = verticies[i]
		}
	}
	device_context->Unmap(vertex_buffer, 0)
	device_context->Draw(u32(verticies_count), 0)

	verticies_count = 0
}

@(private)
resolve_msaa :: proc() {
	back_buffer: ^D3D11.ITexture2D
	swapchain->GetBuffer(0, D3D11.ITexture2D_UUID, (^rawptr)(&back_buffer))

	device_context->ResolveSubresource(back_buffer, 0, msaa_render_target, 0, .B8G8R8A8_UNORM)

	back_buffer->Release()
}

swap_buffers :: proc(vsync: bool) {
	resolve_msaa()
	if vsync {
		swapchain->Present(1, {})
	} else {
		swapchain->Present(0, {})
	}
}

set_scissor :: proc(x, y, width, height: f32) {
	if (verticies_count > 0) {
		end_render()
	}

	rect := D3D11.RECT {
		left   = i32(x),
		top    = i32(y),
		right  = i32(x) + i32(width),
		bottom = i32(y) + i32(height),
	}
	device_context->RSSetScissorRects(1, &rect)
}

disable_scissor :: proc() {
	if (verticies_count > 0) {
		end_render()
	}

	rect := D3D11.RECT {
		left   = 0,
		top    = 0,
		right  = i32(viewport.Width),
		bottom = i32(viewport.Height),
	}
	device_context->RSSetScissorRects(1, &rect)
}

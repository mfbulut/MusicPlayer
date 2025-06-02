cbuffer constants : register(b0)
{
    float2 rn_screensize;
    float screenPxRange;
}

struct vs_in {
	float2 position : POS;
	float2 texcoord : TEX;
	float4 color    : COL;
};

struct vs_out {
	float4 position : SV_POSITION;
	float2 texcoord : TEX;
	float4 color    : COL;
};

Texture2D    mytexture : register(t0);
SamplerState mysampler : register(s0);

vs_out vs_main(vs_in input) {
	vs_out output;
    output.position = float4(input.position * rn_screensize - float2(1, -1), 0, 1);
	output.texcoord = input.texcoord;
	output.color    = input.color;
	return output;
}

float4 ps_main(vs_out input) : SV_TARGET {
	if(input.texcoord.x < -0.5) {
		return input.color;
	} else {
    	return mytexture.Sample(mysampler, input.texcoord) * input.color;
	}
}
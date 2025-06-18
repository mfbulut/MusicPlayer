cbuffer constants : register(b0)
{
    float2 rn_screensize;
    float time;
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
	float2 screen_pos : POS;
};

Texture2D    mytexture : register(t0);
SamplerState mysampler : register(s0);

vs_out vs_main(vs_in input) {
	vs_out output;
    output.position = float4(input.position * rn_screensize - float2(1, -1), 0, 1);
	output.texcoord = input.texcoord;
	output.color    = input.color;
	output.screen_pos = input.position;
	return output;
}

float3 ScreenSpaceDither( float2 vScreenPos )
{
	float3 vDither = dot( float2( 171.0, 231.0 ), vScreenPos.xy + time).xxx;
	vDither.rgb = frac( vDither.rgb / float3( 103.0, 71.0, 97.0 ) ) - float3( 0.5, 0.5, 0.5 );
	return ( vDither.rgb / 255.0 ) * 0.375;
}

float4 ps_main(vs_out input) : SV_TARGET {
	if(input.texcoord.x < -0.5) {
		return input.color + float4(ScreenSpaceDither(input.screen_pos), 0) * 2;
	} else {
    	return mytexture.Sample(mysampler, input.texcoord) * input.color;
	}
}
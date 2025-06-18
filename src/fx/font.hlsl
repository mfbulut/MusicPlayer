cbuffer constants : register(b0)
{
    float2 rn_screensize; // 2 / width, -2 / height
    float time;
    float screenPxRange;
}

struct Input {
	float4 position : SV_POSITION;
	float2 texcoord : TEX;
	float4 color    : COL;
};

Texture2D    mytexture : register(t0);
SamplerState mysampler : register(s0);

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

float4 ps_main(Input input) : SV_TARGET {
    float3 msd = mytexture.Sample(mysampler, input.texcoord).rgb;

    float sd = median(msd.r, msd.g, msd.b);

    float screenPxDistance = screenPxRange * (sd - 0.5);

    float opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);

    float4 finalColor = opacity * input.color;

    return finalColor;
}
// Bokeh blur by "Xor" https://www.shadertoy.com/view/fljyWd

struct Input {
    float4 position : SV_POSITION;
    float2 texcoord : TEX;
    float4 color    : COL;
};

Texture2D    mytexture : register(t0);
SamplerState mysampler : register(s0);

float4 ps_main(Input input) : SV_TARGET
{
    float2 uv = input.texcoord;

    float2 radius =  0.0004;

    float4 result = float4(0, 0, 0, 0);
    float2 i = float2(1.0, 1.0);

    float2x2 rot = float2x2(0.0, 0.061, 1.413, 0.0) - 0.737;

    while (i.x < 32.0)
    {
        radius = mul(radius, rot);
        float4 sample = mytexture.Sample(mysampler, uv + radius * i);
        result += exp(sample / 0.1);
        i += 1.0 / i;
    }

    result = log(result) - 5.0;
    result /= result.a;
    result *= input.color;

    return result;
}
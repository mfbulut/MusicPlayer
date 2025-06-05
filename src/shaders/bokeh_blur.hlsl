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

    float angle = 0.1;
    float2 d = float2(sin(angle), cos(angle));

    float2 p = d * d.yx / 200.0;

    float4 O = float4(0, 0, 0, 0);
    float2 i = float2(1.0, 1.0);

    float2x2 rot = float2x2(0.0, 0.061, 1.413, 0.0) - 0.737;

    while (i.x < 32.0)
    {
        p = mul(p, rot);
        float4 sample = mytexture.Sample(mysampler, uv + p * i);
        O += exp(sample / 0.1);
        i += 1.0 / i;
    }

    O = log(O) - 5.0;
    O /= O.a;
    O *= input.color;

    return O;
}
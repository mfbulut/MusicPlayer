// Gaussian blur https://www.shadertoy.com/view/ltScRG

// 16x acceleration of https://www.shadertoy.com/view/4tSyzy
// by applying gaussian at intermediate MIPmap level.

struct Input {
    float4 position : SV_POSITION;
    float2 texcoord : TEX;
    float4 color    : COL;
};

Texture2D    mytexture : register(t0);
SamplerState mysampler : register(s0);

// Constants
static const int samples = 45;
static const int LOD = 2;         // gaussian done on MIPmap at scale LOD
static const int sLOD = 1 << LOD; // tile size = 2^LOD
static const float sigma = float(samples) * 0.25;

float gaussian(float2 i) {
    i /= sigma;
    return exp(-0.5 * dot(i, i)) / (6.28 * sigma * sigma);
}

float4 blur(Texture2D sp, SamplerState samp, float2 U, float2 scale) {
    float4 O = float4(0, 0, 0, 0);
    int s = samples / sLOD;

    for (int i = 0; i < s * s; i++) {
        float2 d = float2(i % s, i / s) * float(sLOD) - float(samples) / 2.0;
        O += gaussian(d) * sp.SampleLevel(samp, U + scale * d, float(LOD));
    }

    return O / O.a;
}

float4 ps_main(Input input) : SV_TARGET
{
    float2 uv = input.texcoord;

    float2 iChannelResolution = float2(1080, 1080);

    float4 result = blur(mytexture, mysampler, uv, 1.0 / iChannelResolution);
    return result;
}
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

/*

// Gaussian version

struct Input {
    float4 position : SV_POSITION;
    float2 texcoord : TEX;
    float4 color    : COL;
};

Texture2D    mytexture : register(t0);
SamplerState mysampler : register(s0);

// Constants
static const int samples = 35;
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

    // Assuming texture dimensions - you'll need to pass these as constants
    // or use GetDimensions() to get actual texture size
    float2 iResolution = float2(1920, 1080); // Replace with actual resolution
    float2 iChannelResolution = float2(1920, 1080); // Replace with actual texture resolution

    float4 result = blur(mytexture, mysampler, uv, 1.0 / iChannelResolution);
    return result;
}
*/
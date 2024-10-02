#ifndef UNIVERSAL_PARALLAX_MAPPING_INCLUDED
#define UNIVERSAL_PARALLAX_MAPPING_INCLUDED

// Return view direction in tangent space, make sure tangentWS.w is already multiplied by GetOddNegativeScale()
half3 GetViewDirectionTangentSpace(half4 tangentWS, half3 normalWS, half3 viewDirWS)
{
    // must use interpolated tangent, bitangent and normal before they are normalized in the pixel shader.
    half3 unnormalizedNormalWS = normalWS;
    const half renormFactor = 1.0 / length(unnormalizedNormalWS);

    // use bitangent on the fly like in hdrp
    // IMPORTANT! If we ever support Flip on double sided materials ensure bitangent and tangent are NOT flipped.
    half crossSign = (tangentWS.w > 0.0 ? 1.0 : -1.0); // we do not need to multiple GetOddNegativeScale() here, as it is done in vertex shader
    half3 bitang = crossSign * cross(normalWS.xyz, tangentWS.xyz);

    half3 WorldSpaceNormal = renormFactor * normalWS.xyz;       // we want a unit length Normal Vector node in shader graph

    // to preserve mikktspace compliance we use same scale renormFactor as was used on the normal.
    // This is explained in section 2.2 in "surface gradient based bump mapping framework"
    half3 WorldSpaceTangent = renormFactor * tangentWS.xyz;
    half3 WorldSpaceBiTangent = renormFactor * bitang;

    half3x3 tangentSpaceTransform = half3x3(WorldSpaceTangent, WorldSpaceBiTangent, WorldSpaceNormal);
    half3 viewDirTS = mul(tangentSpaceTransform, viewDirWS);

    return viewDirTS;
}

#ifndef BUILTIN_TARGET_API
half2 ParallaxOffset1Step(half height, half amplitude, half3 viewDirTS)
{
    height = height * amplitude - amplitude / 2.0;
    half3 v = normalize(viewDirTS);
    v.z += 0.42;
    return height * (v.xy / v.z);
}
#endif

float2 ParallaxMapping(TEXTURE2D_PARAM(heightMap, sampler_heightMap), half3 viewDirTS, half scale, float2 uv)
{
    half h = SAMPLE_TEXTURE2D(heightMap, sampler_heightMap, uv).g;
    float2 offset = ParallaxOffset1Step(h, scale, viewDirTS);
    return offset;
}

float2 ParallaxMappingChannel(TEXTURE2D_PARAM(heightMap, sampler_heightMap), half3 viewDirTS, half scale, float2 uv, int channel)
{
    half h = SAMPLE_TEXTURE2D(heightMap, sampler_heightMap, uv)[channel];
    float2 offset = ParallaxOffset1Step(h, scale, viewDirTS);
    return offset;
}

float2 SecantMethodReliefMapping(TEXTURE2D_PARAM(heightMap, sampler_heightMap), float2 inddx, float2 inddy, int channel, float2 uv, float3 viewDirTS, float2 offsetScale, float slicesMin, float slicesMax)
{
    // The number of slices depends on VdotN (view angle smaller, slices smaller).
    int slicesNum = ceil(lerp(slicesMax, slicesMin, abs(dot(float3(0, 0, 1), viewDirTS))));
    float deltaHeight = 1.0 * rcp(slicesNum);
    float2 deltaUV = offsetScale.y * viewDirTS.xy * rcp(viewDirTS.z * slicesNum);
    
    float prevHeight = SAMPLE_TEXTURE2D_GRAD(heightMap, sampler_heightMap, uv, inddx, inddy)[channel];
    float2 currUVOffset = -deltaUV;
    float currHeight = SAMPLE_TEXTURE2D_GRAD(heightMap, sampler_heightMap, uv + currUVOffset, inddx, inddy)[channel];
    float rayHeight = 1.0 - deltaHeight;
    
    // Linear search
    for (int sliceIndex = 0; sliceIndex < slicesNum; sliceIndex++)
    {
        if (currHeight > rayHeight)
            break;
        prevHeight = currHeight;
        rayHeight -= deltaHeight;
        currUVOffset -= deltaUV;
        currHeight = SAMPLE_TEXTURE2D_GRAD(heightMap, sampler_heightMap, uv + currUVOffset, inddx, inddy)[channel];
    }
    float pt0 = rayHeight + deltaHeight;
    float pt1 = rayHeight;
    float delta0 = pt0 - prevHeight;
    float delta1 = pt1 - currHeight;
    float delta;
    float2 offset;
    // Secant method to affine the search
    // Ref: Faster Relief Mapping Using the Secant Method - Eric Risser
    for (int i = 0; i < 3; ++i)
    {
        // intersectionHeight is the height [0..1] for the intersection between view ray and heightfield line
        float intersectionHeight = (pt0 * delta1 - pt1 * delta0) / (delta1 - delta0);
        // Retrieve offset require to find this intersectionHeight
        currUVOffset = -(1 - intersectionHeight) * deltaUV * slicesNum;
        currHeight = SAMPLE_TEXTURE2D_GRAD(heightMap, sampler_heightMap, uv + currUVOffset, inddx, inddy)[channel];
        delta = intersectionHeight - currHeight;
        if (abs(delta) <= 0.01)
            break;
        // intersectionHeight < currHeight => new lower bounds
        if (delta < 0.0)
        {
            delta1 = delta;
            pt1 = intersectionHeight;
        }
        else
        {
            delta0 = delta;
            pt0 = intersectionHeight;
        }
    }
    
    float2 parallaxUV = uv + currUVOffset;
    return parallaxUV;
}

#endif // UNIVERSAL_PARALLAX_MAPPING_INCLUDED

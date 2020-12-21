#define PI 3.14159265359
#define EPS 0.0001

float Pow4(float v)
{
    return v * v * v * v;
}

float Pow5(float v)
{
    return v * v * v * v * v;
}

//法线分布项，这里有三种
//D1：γ=2，代表基础底层材质（Base Material）的反射，可为各项异性（anisotropic） 或各项同性（isotropic）的金属或非金属
float D_GTR1(float roughness, float NdotH)
{
    float a2 = lerp(0.002, 1, roughness); //lerp一下避免出现奇怪的半点
    float cos2th = NdotH * NdotH;
    float den = (1.0 + (a2 - 1.0) * cos2th);

    return (a2 - 1.0) / (PI * log(a2) * den); //！！！PI
}

//D2：γ=1，代表基础材质上的清漆层（ClearCoat Layer）的反射，一般为各项同性（isotropic）的非金属材质，即清漆层（ClearCoat Layer）
float D_GTR2(float alpha, float dotNH)
{
    float a2 = lerp(0.002, 1, alpha);
    float cos2th = dotNH * dotNH;
    float den = (1.0 + (a2 - 1.0) * cos2th);

    return a2 / (PI * den * den);
}

//D3：各向异性
float D_GTR2_aniso(float dotHX, float dotHY, float dotNH, float ax, float ay)
{
    float deno = dotHX * dotHX / (ax * ax) + dotHY * dotHY / (ay * ay) + dotNH * dotNH;
    return 1.0 / (PI * ax * ay * deno * deno);
}

// Normal distribution functions
float IsotropyNDF(float NdotH, float roughness)
{
    float alpha = Pow4(roughness);
    float NdotH2 = NdotH * NdotH;
    float denominator = PI * pow((alpha - 1) * NdotH2 + 1, 2);
    return alpha / denominator;
}

float AnisotropyNDF(float NdotH, float roughness, float anisotropy, float HdotT, float HdotB)
{
    float aspect = sqrt(1.0 - 0.9 * anisotropy);
    float alpha = roughness * roughness;

    float roughT = alpha / aspect;
    float roughB = alpha * aspect;

    float alpha2 = alpha * alpha;
    float NdotH2 = NdotH * NdotH;
    float HdotT2 = HdotT * HdotT;
    float HdotB2 = HdotB * HdotB;

    float denominator = PI * roughT * roughB * pow(HdotT2 / (roughT * roughT) + HdotB2 / (roughB * roughB) + NdotH2, 2);
    return 1 / denominator;
}

// 漫反射
// Disney漫反射
float3 DisneyDiffuse(float3 col, float HdotV, float NdotV, float NdotL, float roughness)
{
    float F90 = 0.5 + 2 * roughness * HdotV * HdotV;
    float FdV = 1 + (F90 - 1) * Pow5(1 - NdotV);
    float FdL = 1 + (F90 - 1) * Pow5(1 - NdotL);
    return FdV * FdL / PI;
}

// Schlick Fresnel
float3 fresnel(float3 F0, float NdotV)
{
    return F0 + (1 - F0) * Pow5(1 - NdotV);
}

float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
    return F0 + (max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
}

//添加了lerp，不过好像没太大差别
float3 F0_X(float lerpvalue, float3 col, float metalness)
{
    return lerp(float3(lerpvalue, lerpvalue, lerpvalue), col, metalness);
}

// GGX
float cookTorranceGAF(float NdotH, float NdotV, float HdotV, float NdotL)
{
    float firstTerm = 2 * NdotH * NdotV / HdotV;
    float secondTerm = 2 * NdotH * NdotL / HdotV;
    return min(1, min(firstTerm, secondTerm));
}

float schlickBeckmannGAF(float NdotL, float NdotV, float roughness)
{
    float kInDirectLight = pow(Pow4(roughness) + 1, 2) / 8;
    float kInIBL = pow(Pow4(roughness), 2) / 8;
    float GLeft = NdotL / lerp(NdotL, 1, kInDirectLight);
    float GRight = NdotV / lerp(NdotV, 1, kInDirectLight);
    return GLeft * GRight;
}

// Smith GGX G项，各项同性版本
float smithG_GGX(float NdotV, float alphaG)
{
    float a = alphaG * alphaG;
    float b = NdotV * NdotV;
    return 1 / (NdotV + sqrt(a + b - a * b));
}

// Smith GGX G项，各项异性版本
float smithG_GGX_aniso(float dotVN, float dotVX, float dotVY, float ax, float ay)
{
    return 1.0 / (dotVN + sqrt(pow(dotVX * ax, 2.0) + pow(dotVY * ay, 2.0) + pow(dotVN, 2.0)));
}

// GGX清漆几何项
float G_GGX(float dotVN, float alphag)
{
    float a = alphag * alphag;
    float b = dotVN * dotVN;
    return 1.0 / (dotVN + sqrt(a + b - a * b));
}

//SH
float3 SH3band(float3 normal, float3 albedo, int band) 
{
    float3 skyLightBand2 = SHEvalLinearL0L1(float4(normal, 1));
    float3 skyLightBand3 = ShadeSH9(float4(normal, 1));
    return ((band == 2)? skyLightBand2 : skyLightBand3) * albedo * 50; //*50加大天光影响
}

//-----------------------------------
// Helpers
float3 gammaCorrection(float3 v)
{
    return pow(v, 1.0 / 2.2);
}

float3 sRGB2Lin(float3 col)
{
    return pow(col, 2.2);
}
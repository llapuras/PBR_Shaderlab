﻿Shader "Alfx/AlfxPBR"
{
	//按照rtr书上的公式版本进行实现
	Properties
	{   
		[Header(Parameters)]
		[MaterialToggle] EnableDiffuse("Enable Diffuse", Float) = 1
	    [MaterialToggle] EnableSpecular("Enable Specular", Float) = 1
	    [MaterialToggle] EnableSH("Enable SH", Float) = 1
		_NDF("NDF mode", Int) = 1

		[Header(Debug Mode)]
		[MaterialToggle] DebugNormalMode("Debug Normal Mode", Float) = 0

		[Header(BDRF)]
		[MaterialToggle] aD("D", Float) = 1
        [MaterialToggle] aF("F", Float) = 1
	    [MaterialToggle] aG("G", Float) = 1

		[Header(Textures)]
		_MainTex("Basecolor Map", 2D) = "white" {}
		_NormalMap("Normal Map", 2D) = "bump" {}
		_MetalnessMap("Metalness Map", 2D) = "black" {}
		_RoughnessMap("Roughness Map", 2D) = "black" {}
		_OcclusionMap("Occlusion Map", 2D) = "white" {}

		_Tint("Tint", Color) = (1 ,1 ,1 ,1)
		_FresnelColor("Fresnel Color (F0)", Color) = (1.0, 1.0, 1.0, 1.0)

		_Metallic("Metallic", Range(0, 1)) = 0
		_Roughness("Roughness", Range(0, 1)) = 0.5
		_Anisotropy("Anisotropy", Range(0,1)) = 0
		_LUT("LUT", 2D) = "white" {}

		[Header(TestProp)]
		_Test("test", Range(0, 1)) = 0
	}

	SubShader
	{
		Tags { "RenderType" = "Opaque" }
		LOD 100

		Pass
		{
			Tags {
				"LightMode" = "ForwardBase"
			}
			CGPROGRAM


			#pragma target 3.0

			#pragma vertex vert
			#pragma fragment frag

			#include "UnityStandardBRDF.cginc" 
		    #include "AlfxPBRLib.cginc" 
			#include "AutoLight.cginc" 
			#include "Lighting.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 tangent: TANGENT;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 normal : TEXCOORD1;
				float3 tangent: TEXCOORD2;
				float3 bitangent: TEXCOORD3;
				float3 worldPos : TEXCOORD4;

				/*float3 tm : TEXCOORD7;
				float3 bm : TEXCOORD8;
				float3 nm : TEXCOORD9;*/

				float3 tangentLocal: TEXCOORD5;
				float3 bitangentLocal: TEXCOORD6;

				SHADOW_COORDS(5)//实时光遮蔽
			};

			float4 _Tint, _FresnelColor;
			float _Metallic, _Roughness, _Anisotropy;
			float _NDF;
			sampler2D _MainTex, _RoughnessMap, _NormalMap, _MetalnessMap, _OcclusionMap;
			float4 _MainTex_ST, _RoughnessMap_ST, _NormalMap_ST, _MetalnessMap_ST, _OcclusionMap_ST;
			sampler2D _LUT;

			//test
			float _Test;

			//para
			int EnableDiffuse, EnableSpecular, aD, aF, aG, DebugNormalMode, EnableSH;

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				
				// Normal mapping parameters
				half3 wNormal = UnityObjectToWorldNormal(v.normal);
				half3 wTangent = UnityObjectToWorldDir(v.tangent.xyz);
				half tangentSign = v.tangent.w * unity_WorldTransformParams.w;
				half3 wBitangent = cross(wNormal, wTangent) * tangentSign;
				o.tangent = normalize(mul(unity_ObjectToWorld, v.tangent).xyz);
				o.normal = normalize(UnityObjectToWorldNormal(v.normal));
				o.bitangent = normalize(cross(o.normal, o.tangent.xyz));

				/*o.tm = half3(o.tangent.x, o.bitangent.x, o.normal.x);
				o.bm = half3(o.tangent.y, o.bitangent.y, o.normal.y);
				o.nm = half3(o.tangent.z, o.bitangent.z, o.normal.z);*/

				o.tangentLocal = v.tangent;
				o.bitangentLocal = normalize(cross(v.normal, o.tangentLocal));

				TRANSFER_SHADOW(o);
				return o;
			}

			float4 frag(v2f i) : SV_Target
			{
				//realtime light shadow
				float shadow = SHADOW_ATTENUATION(i);

				//光照、视线、半角
				float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
				float3 lightColor = _LightColor0.rgb;
				float3 halfVec = normalize(lightDir + viewDir);//相关：Blinn-phong

				//normal map
				float3x3 TBN = transpose(float3x3(i.tangent, i.bitangent, i.normal));
				float3 normal = UnpackNormal(tex2D(_NormalMap, i.uv)); //！！！不要忘记unpack= - =
			    normal = mul(TBN, normalize(normal));
				i.normal = normal;

				// This assumes that the maximum param is right if both are supplied (range and map)
				float roughness = max(_Roughness + EPS, tex2D(_RoughnessMap, i.uv).r) + EPS;
				float metalness = max(_Metallic + EPS, tex2D(_MetalnessMap, i.uv).r) + EPS;
				float occlusion = (tex2D(_OcclusionMap, i.uv).r);

				float4 baseColor = tex2D(_MainTex, i.uv) * _Tint;
				float4 albedo = baseColor * (1.0 - metalness);// *occlusion;

				// AdotB，emmm反正先排列组合全写上了要用啥拿啥吧
				// 最小值设置0.00001是为了防止除数为0的情况报error
				float NdotL = max((dot(i.normal, lightDir)), EPS);
				float NdotH = max((dot(i.normal, halfVec)), EPS);
				float HdotV = max((dot(halfVec, viewDir)), EPS);
				float NdotV = max((dot(i.normal, viewDir)), EPS);
				float LdotH = max((dot(lightDir, halfVec)), EPS);
				float VdotH = max((dot(viewDir, halfVec)), EPS);
				float HdotT = dot(halfVec, i.tangentLocal);
				float HdotB = dot(halfVec, i.bitangentLocal);

				//----------------------------------------
				//迪士尼漫反射
				float3 DisneyTerm = DisneyDiffuse(albedo, LdotH, NdotL, VdotH, roughness);
				
				//----------------------------------------
				//D-法线分布函数
				float D = trowbridgeReitzAnisotropicNDF(NdotH, roughness, _Anisotropy, HdotT, HdotB);
				D = trowbridgeReitzNDF(NdotH, roughness);

				//G-遮蔽
				float G = schlickBeckmannGAF(NdotV, roughness) * schlickBeckmannGAF(NdotL, roughness);

				//F-fresnel
				float3 F0 = F0_X(0.04, _FresnelColor, metalness);
				//float3 F0 = lerp(float3(0.04, 0.04, 0.04), _FresnelColor, metalness);
				float3 F = fresnel(F0, HdotV);

				//漫反射系数
				float3 kd = (1 - F) * (1 - metalness);
				
				float3 Gterm = ((G * aG != 0) ? G : 1);
				float3 Dterm = ((D * aD != 0) ? D : 1);
				float3 Fterm = ((F * aF != 0) ? F : 1);
				float3 SpecularResult = (aD + aF + aG == 0 ? 0 : (Gterm * Dterm * Fterm * 0.25) / (NdotV * NdotL));

				float3 diffColor_result = kd * NdotL * EnableDiffuse * lightColor * albedo;
				float3 specColor_result = SpecularResult * EnableSpecular * lightColor * albedo;
				float3 DirectLightResult = diffColor_result + specColor_result;

				//----------------------------------------
				//indirectal light
				//ibldiffuse: SH skylight
				float3 iblDiffuse = SH3band(i.normal, albedo);
				float3 iblDiffuseResult = (EnableSH == 1) ? iblDiffuse : 0;
				
				//iblspecular
				float2 brdfUV = float2(NdotV, _Roughness);
				float2 preBRDF = tex2D(_LUT, brdfUV).xy;
				float mip_roughness = roughness * (1.7 - 0.7 * roughness);
				float3 reflectVec = reflect(-viewDir, i.normal);
				half mip = mip_roughness * UNITY_SPECCUBE_LOD_STEPS;
				float3 envSample = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectVec, mip);
				float3 iblSpecular = envSample;// DecodeHDR(envSample, unity_SpecCube0_HDR);

				float3 iblSpecularResult = iblSpecular;
				float3 IndirectResult = iblDiffuseResult + iblSpecularResult;
	
				float4 result = float4(DirectLightResult + IndirectResult, 1);
				result.xyz = (DebugNormalMode == 1) ? i.normal * 0.5 + 0.5 : result.xyz;
				return float4((result.xyz), 1.0);
			}

			ENDCG
		}
	}
}
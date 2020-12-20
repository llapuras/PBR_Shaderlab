Shader "Alfx/AlfxPBR_best"
{
	//按照rtr书上的公式版本进行实现
	Properties
	{   
		[Header(Parameters)]
		[MaterialToggle] EnableDiffuse("Enable Diffuse", Float) = 1
	    [MaterialToggle] EnableSpecular("Enable Specular", Float) = 1

		[Header(Debug Mode)]
		[MaterialToggle] DebugNormalMode("Debug Normal Mode", Float) = 0

		[Header(BDRF)]
		[MaterialToggle] aD("D", Float) = 1
        [MaterialToggle] aF("F", Float) = 1
	    [MaterialToggle] aG("G", Float) = 1

		_Ior("IOR", Range(0, 1)) = 1

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

				float3 tangentLocal: TEXCOORD5;
				float3 bitangentLocal: TEXCOORD6;

				SHADOW_COORDS(5)//实时光遮蔽
			};

			float4 _Tint, _FresnelColor;
			float _Metallic, _Roughness, _Anisotropy;
			float _Ior;
			sampler2D _MainTex, _RoughnessMap, _NormalMap, _MetalnessMap, _OcclusionMap;
			float4 _MainTex_ST, _RoughnessMap_ST, _NormalMap_ST, _MetalnessMap_ST, _OcclusionMap_ST;
			sampler2D _LUT;

			//para
			int EnableDiffuse, EnableSpecular, aD, aF, aG, DebugNormalMode;

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				
				// Normal mapping parameters
				o.tangent = normalize(mul(unity_ObjectToWorld, v.tangent).xyz);
				o.normal = normalize(UnityObjectToWorldNormal(v.normal));
				o.bitangent = normalize(cross(o.normal, o.tangent.xyz));

				o.tangentLocal = v.tangent;
				o.bitangentLocal = normalize(cross(v.normal, o.tangentLocal));

				TRANSFER_SHADOW(o);
				return o;
			}

			float4 frag(v2f i) : SV_Target
			{
				//realtime light AO
				float shadow = SHADOW_ATTENUATION(i);

				//光照、视线、半角
				float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
				float3 lightColor = _LightColor0.rgb;
				float3 halfVec = normalize(lightDir + viewDir);//相关：Blinn-phong

				//normal map
				float3x3 TBN = transpose(float3x3(i.tangent, i.bitangent, i.normal));
				float3 tangentNormal = tex2D(_NormalMap, i.uv).xyz;
				float3 normal = mul(TBN, normalize(tangentNormal));

				//...
				float3 reflectVec = -reflect(viewDir, normal);

				i.normal.xyz = normal.xyz;


				// This assumes that the maximum param is right if both are supplied (range and map)
				float roughness = (max(_Roughness + EPS, tex2D(_RoughnessMap, i.uv)).r);
				float metalness = (max(_Metallic + EPS, tex2D(_MetalnessMap, i.uv)).r);
				float occlusion = (tex2D(_OcclusionMap, i.uv).r);

				float4 baseColor = tex2D(_MainTex, i.uv) * _Tint;
				//float perceptualRoughness = _Roughness;			
				//float squareRoughness = roughness * roughness;

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

				float lightIntensity = NdotL > 0 ? 1 : 0;

				//迪士尼漫反射
				float DisneyTerm = DisneyDiffuse(NdotV, NdotL, NdotH, roughness);
				float4 disneyDiffuse = DisneyTerm; 

				//D-法线分布函数
				//float lerpSquareRoughness = pow(lerp(0.001, 1, roughness), 2);//Unity把roughness lerp到了0.002
				//float D = lerpSquareRoughness / (pow((pow(NdotH, 2) * (lerpSquareRoughness - 1) + 1), 2));// *PI);
				float D = trowbridgeReitzNDF(NdotH, roughness);
				D = trowbridgeReitzAnisotropicNDF(NdotH, roughness, _Anisotropy, HdotT, HdotB);

				//G-遮蔽
				/*float kInDirectLight = pow(squareRoughness + 1, 2) / 8;
				float kInIBL = pow(squareRoughness, 2) / 8;
				float GLeft = NdotL / lerp(NdotL, 1, kInDirectLight);
				float GRight = NdotV / lerp(NdotV, 1, kInDirectLight);
				float G = GLeft * GRight;*/
				float G = schlickBeckmannGAF(NdotV, roughness) * schlickBeckmannGAF(NdotL, roughness);

				//F-fresnel
				//float3 F = lerp(F0(_Ior), diffColor, _Metallic) + (1 - lerp(F0(_Ior), diffColor, _Metallic)) * Pow5(1 - NdotV);
				float3 F0 = lerp(float3(0.04, 0.04, 0.04), _FresnelColor * baseColor, metalness);
				float3 F = fresnel(F0, NdotV);

				//漫反射系数
				float3 kd = (1 - F) * (1 - metalness);
				
				float3 Gterm = ((G * aG != 0) ? G : 1);
				float3 Dterm = ((D * aD != 0) ? D : 1);
				float3 Fterm = ((F * aF != 0) ? F : 1);
				float3 SpecularResult = (aD + aF + aG == 0 ? 0 : (Gterm * Dterm * Fterm * 0.25) / (NdotV * NdotL));

				float3 diffColor_result = kd * max(dot(normal, lightDir), 0.0) * EnableDiffuse * lightColor * baseColor * PI;
				float3 specColor_result = SpecularResult * EnableSpecular * lightColor * baseColor * PI;
				float3 DirectLightResult = diffColor_result + specColor_result;

				float3 iblDiffuseResult = 0;
				float3 iblSpecularResult = 0;
				float3 IndirectResult = iblDiffuseResult + iblSpecularResult;
	
				float4 result = float4(DirectLightResult + IndirectResult, 1);
				result.xyz = (DebugNormalMode == 1) ? normal * 0.5 + 0.5 : result.xyz;
				return float4((result.xyz), 1.0);
			}

			ENDCG
		}
	}
}
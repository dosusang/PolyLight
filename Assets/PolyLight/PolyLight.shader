Shader "Test/PolyLight"
{
    Properties
    {
        _BaseMap ("Example Texture", 2D) = "white" {}
        _BaseColor ("Example Colour", Color) = (0, 0.66, 0.73, 1)
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Opaque"
            "Queue"="Geometry"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "AreaLight.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        float4 _BaseColor;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "Unlit"

            HLSLPROGRAM
            #pragma vertex UnlitPassVertex
            #pragma fragment UnlitPassFragment

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
                float3 posWS : TEXCOORD1;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            Varyings UnlitPassVertex(Attributes input)
            {
                Varyings output;

                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = positionInputs.positionCS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.color = input.color;
                output.posWS = positionInputs.positionWS;
                return output;
            }

            float4 UnlitPassFragment(Varyings input) : SV_Target
            {
                float4x3 verts = {
                    -3,0.1,0,
                    3,0.1,0,
                    3,2.5,0,
                    -3,2.5,0,
                };

                float3 N = float3(0,1,0);
                float3 V = GetWorldSpaceViewDir(input.posWS);
                float3 T1, T2;
                T1 = normalize(V - N*dot(V,N));
                T2 = cross(N, T1);

                // 基于法线和视线构建的一个正交坐标系，将verts变换到此坐标系内的好处是方便后续采样灯光贴图，以及单位向量的z值即是辐照度
                float3x3 ot = {
                    T1,T2,N
                };

                verts[0] = mul(ot, verts[0] - input.posWS);
                verts[1] = mul(ot, verts[1] - input.posWS);
                verts[2] = mul(ot, verts[2] - input.posWS);
                verts[3] = mul(ot, verts[3] - input.posWS);

                float3 f = 0;
                // 辐照度(漫反射) 求解了多边形光源的漫反射项（本质是一个余弦分布的球面函数）
                // 内部使用[https://www.advances.realtimerendering.com/s2016/s2016_ltc_rnd.pdf]的多边形球面积分求解公式
                // f用于接收平均辐照方向
                float radiance = PolygonIrradiance(verts, f);

                // 如何求解specular(BRDF高光)
                // 目标也是一个球面分布函数，可以使用一个使用目标矩阵M将cos余弦分布拟合到目标球面分布函数 ltc = mul(M, cos)
                // 使用一个预计算结构存储不同roughness和不同viewAngle下的目标矩阵M，运行时获取此目标矩阵(如何预计算这个存储结构?答案是离线遍历拟合)
                // 因为我们能求解的只有余弦分布，所以需要先将ltc变换回余弦分布： cos = mul(inverse(M), ltc)
                float specular = 0;
                
                return float4(radiance.xxx, 1);
            }
            ENDHLSL
        }
    }
}
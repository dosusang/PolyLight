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

            half4 UnlitPassFragment(Varyings input) : SV_Target
            {
                float4x3 verts = {
                    -3,0.1,0,
                    3,0.1,0,
                    3,2.5,0,
                    -3,2.5,0,
                };

                verts[0] = verts[0] - input.posWS;
                verts[1] = verts[1] - input.posWS;
                verts[2] = verts[2] - input.posWS;
                verts[3] = verts[3] - input.posWS;

                float3 N = float3(0,1,0);
                float3 f = 0;

                // compute in world space, output is Irradiance
                float ira = dot(PolygonIrradiance(verts, f), N);
                return float4(ira.xxx, 1);

                // float3 V = GetWorldSpaceViewDir(input.posWS);
                // float3 T1, T2;
                // T1 = normalize(V - N*dot(V,N));
                // T2 = cross(N, T1);
                // float3x3 ot = {
                //     T1,T2,N
                // };
                // verts[0] = mul(ot, verts[0] - input.posWS);
                // verts[1] = mul(ot, verts[1] - input.posWS);
                // verts[2] = mul(ot, verts[2] - input.posWS);
                // verts[3] = mul(ot, verts[3] - input.posWS);


            }
            ENDHLSL
        }
    }
}
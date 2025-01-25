Shader "Custom/RayTracing"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            // --- RNG Stuff ---

            // PCG (permuted congruential generator). Thanks to:
            // www.pcg-random.org and www.shadertoy.com/view/XlGcRh
            uint NextRandom(inout uint state)
            {
                state = state * 747796405 + 2891336453;
                uint result = ((state >> ((state >> 28) + 4)) ^ state) * 277803737;
                result = (result >> 22) ^ result;
                return result;
            }

            float RandomValue(inout uint state)
            {
                return NextRandom(state) / 4294967295.0; // 2^32 - 1
            }

            // Random value in normal distribution (with mean=0 and sd=1)
            float RandomValueNormalDistribution(inout uint state)
            {
                // Thanks to https://stackoverflow.com/a/6178290
                float theta = 2 * 3.1415926 * RandomValue(state);
                float rho = sqrt(-2 * log(RandomValue(state)));
                return rho * cos(theta);
            }

            // Calculate a random direction
            float3 RandomDirection(inout uint state)
            {
                // Thanks to https://math.stackexchange.com/a/1585996
                float x = RandomValueNormalDistribution(state);
                float y = RandomValueNormalDistribution(state);
                float z = RandomValueNormalDistribution(state);
                return normalize(float3(x, y, z));
            }

            float2 RandomPointInCircle(inout uint rngState)
            {
                float angle = RandomValue(rngState) * 2 * UNITY_PI;
                float2 pointOnCircle = float2(cos(angle), sin(angle));
                return pointOnCircle * sqrt(RandomValue(rngState));
            }

            struct Ray
            {
                float3 origin;
                float3 direction;
            };

            Ray CreateRay(float3 origin, float3 direction)
            {
                Ray r;
                r.origin = origin;
                r.direction = direction;
                return r;
            }

            float3 RayAt(Ray r, float t)
            {
                return r.origin + r.direction * t;
            }

            struct HitInfo
            {
                float3 hitPosition;
                float distance;
                float3 albedo;
                float3 emission;
                float3 normal;
                float emissionStrength;
                bool frontFace;
            };

            struct Sphere
            {
                float3 albedo;
                float3 emission;
                float emissionStrength;
                float3 center;
                float radius;
            };

            StructuredBuffer<Sphere> SpheresBuffer;
            int NumOfSpheres;

            bool RaySphereIntersection(Ray r, Sphere s, inout HitInfo hitInfo)
            {
                float3 oc = s.center - r.origin;
                float a = dot(r.direction, r.direction);
                float h = -2.0 * dot(r.direction, oc);
                float c = dot(oc, oc) - s.radius * s.radius;

                float discriminant = h * h - 4 * a * c;
                if (discriminant < 0.0f) return false;

                float root = (-h - sqrt(discriminant)) / (2.0f * a);
                if (root <= 0.001f || hitInfo.distance <= root)
                {
                    root = (-h + sqrt(discriminant)) / (2.0f * a);
                    if (root <= 0.001f || hitInfo.distance <= root)
                    {
                        return false;
                    }
                }

                hitInfo.hitPosition = RayAt(r, root);
                hitInfo.normal = normalize(hitInfo.hitPosition - s.center);
                if (dot(r.direction, hitInfo.normal) > 0.0)
                {
                    hitInfo.normal = -hitInfo.normal;
                    hitInfo.frontFace = false;
                }
                else
                {
                    hitInfo.frontFace = true;
                }

                hitInfo.distance = root;
                hitInfo.emission = s.emission;
                hitInfo.albedo = s.albedo;
                hitInfo.emissionStrength = s.emissionStrength;
                return true;
            }

            HitInfo CreateHitInfo()
            {
                HitInfo h;
                h.albedo = 0.0;
                h.distance = 1.#INF;
                h.emission = 0.0;
                h.normal = 0.0;
                h.hitPosition = 0.0;
                h.emissionStrength = 0.0;

                return h;
            }

            void TestSceneIntersection(Ray r, inout HitInfo hitInfo)
            {
                // Spheres
                for (int i = 0; i < NumOfSpheres; i++)
                {
                    RaySphereIntersection(r, SpheresBuffer[i], hitInfo);
                }
            }

            int NumberOfBounces;

            float3 GetRayColor(Ray r, inout uint rngState)
            {
                float3 throughput = 1.0;
                float3 color = 0.0;
                float a = r.direction.y;
                for (int b = 0; b < NumberOfBounces; b++)
                {
                    HitInfo hitInfo = CreateHitInfo();
                    TestSceneIntersection(r, hitInfo);

                    if (hitInfo.distance >= 1.#INF)
                    {
                        // color += ((1.0 - a) * float3(0.8, 0.8, 0.8) + float3(0.3, 0.3, 0.3) * a);
                        break;
                    }

                    float3 emittedLight = hitInfo.emission * hitInfo.emissionStrength;
                    color += emittedLight * throughput;

                    r.origin = hitInfo.hitPosition;
                    r.direction = hitInfo.normal + RandomDirection(rngState);

                    throughput *= hitInfo.albedo;
                }
                return color;
            }

            float4x4 CameraLocalToWorldMatrix;
            float3 ViewParams;
            int Frame;
            int RayPerPixel;

            float4 frag(v2f i) : SV_Target
            {
                // Create seed for random number generator
                uint2 numPixels = _ScreenParams.xy;
                uint2 pixelCoord = i.uv * numPixels;
                uint pixelIndex = pixelCoord.y * numPixels.x + pixelCoord.x;
                uint rngState = pixelIndex + Frame * 719393;

                float2 uv = (i.uv - 0.5);

                float3 viewPointLocal = float3(uv, 1.0) * ViewParams;
                float3 viewPoint = mul(CameraLocalToWorldMatrix, float4(viewPointLocal, 1.0));

                float3 origin = _WorldSpaceCameraPos;
                float3 rayDir = normalize(viewPoint - origin);

                Ray r = CreateRay(origin, rayDir);

                int rayPerPixel = RayPerPixel;
                float3 color = 0.0;
                for (int i = 0; i < rayPerPixel; i++)
                {
                    color += GetRayColor(r, rngState);
                }


                return float4(color / float(rayPerPixel), 1.0);
            }
            ENDCG
        }
    }
}
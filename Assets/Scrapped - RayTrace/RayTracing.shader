// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/RayTracing"
{
    SubShader
    {
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "UnityCG.cginc"

            float4x4 CameraLocalToWorldMatrix;
            float3 CameraWorldSpacePosition;
            float4x4 CameraInverseProjection;
            float3 ViewParams;
            int Frame;

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

            // float4 vert(appdata_base v) : POSITION
            // {
            //     return UnityObjectToClipPos(v.vertex);
            // }
            // uint wang_hash(inout uint seed)
            // {
            //     seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
            //     seed *= uint(9);
            //     seed = seed ^ (seed >> 4);
            //     seed *= uint(0x27d4eb2d);
            //     seed = seed ^ (seed >> 15);
            //     return seed;
            // }
            //
            // float RandomFloat01(inout uint state)
            // {
            //     return float(wang_hash(state)) / 4294967296.0;
            // }
            //
            // float3 RandomUnitVector(inout uint state)
            // {
            //     float z = RandomFloat01(state) * 2.0f - 1.0f;
            //     float a = RandomFloat01(state) * UNITY_PI;
            //     float r = sqrt(1.0f - z * z);
            //     float x = r * cos(a);
            //     float y = r * sin(a);
            //     return float3(x, y, z);
            // }
            //
            // float3 RandomOnHemisphere(inout uint state)
            // {
            //     float3 p = RandomUnitVector(state) * 2.0 - 1.0;
            //     float lengthSquared = dot(p, p);
            //     for (int i = 0; i < 100; i++)
            //     {
            //         p = RandomUnitVector(state) * 2.0 - 1.0;
            //         lengthSquared = dot(p, p);
            //         if (lengthSquared <= 1)
            //         {
            //             return p / sqrt(lengthSquared);
            //         }
            //     }
            //     return p / sqrt(lengthSquared);
            // }

            struct Ray
            {
                float3 origin;
                float3 direction;
            };

            struct RayHit
            {
                float3 hitPosition;
                float distance;
                float3 normal;
                float3 colour;
                float3 emissive;
            };

            struct RayTracingMaterial
            {
                float3 colour;
            };

            struct Sphere
            {
                float3 position;
                float radius;
                float3 colour;
                float3 emissive;
            };

            bool RaySphereIntersection(Ray r, Sphere s, inout RayHit hitInfo)
            {
                float3 oc = s.position - r.origin;
                float a = dot(r.direction, r.direction);
                float h = -2.0 * dot(r.direction, oc);
                float c = dot(oc, oc) - s.radius * s.radius;

                float discriminant = h * h - 4 * a * c;
                if (discriminant < 0.0f) return false;

                float root = (-h - sqrt(discriminant)) / (2.0f * a);
                // float root = (h - sqrtd) / a;
                if (root <= 0.001f || hitInfo.distance <= root)
                {
                    // root = (h + sqrtd) / a;
                    root = (-h + sqrt(discriminant)) / (2.0f * a);
                    if (root <= 0.001f || hitInfo.distance <= root)
                    {
                        return false;
                    }
                }

                hitInfo.hitPosition = r.origin + root * r.direction;
                hitInfo.normal = normalize(hitInfo.hitPosition - s.position);
                hitInfo.distance = root;
                hitInfo.emissive = s.emissive;
                hitInfo.colour = s.colour;
                return true;
            }

            // Buffers
            StructuredBuffer<Sphere> SpheresBuffer;
            int NumOfSpheres;

            StructuredBuffer<Sphere> SecondSpheres;

            void TestSphereIntersections(inout Ray r, inout RayHit hitInfo)
            {
                for (int i = 0; i < NumOfSpheres; i++)
                {
                    Sphere s = SpheresBuffer[i];
                    RaySphereIntersection(r, s, hitInfo);
                    // bool hitSphere = RaySphereIntersection(r, s, hitInfo);
                    // if (hitSphere)
                    // {
                    //     hitInfo.colour = s.colour;
                    // }
                }
            }

            Ray CreateRay(float3 origin, float3 direction)
            {
                Ray r;
                r.origin = origin;
                r.direction = direction;
                return r;
            }

            Ray GetRayDirection(float2 uv)
            {
                float3 viewPointLocal = float3(uv, 1.0f) * ViewParams;
                float3 viewPoint = mul(CameraLocalToWorldMatrix, float4(viewPointLocal, 1.0f));

                Ray r = CreateRay(CameraWorldSpacePosition, normalize(viewPoint - CameraWorldSpacePosition));
                return r;
            }


            float3 GetRayColor(Ray r, inout uint rngState)
            {
                float a = r.direction.y;
                float3 color = float3(0.0f, 0.0f, 0.0f);
                float3 throughput = float3(1.0f, 1.0f, 1.0f);
                Ray currentRay = r;
                for (int bounce = 0; bounce < 10; bounce++)
                {
                    RayHit hitInfo;
                    hitInfo.distance = 1.#INF;
                    hitInfo.normal = float3(0.0f, 0.0f, 0.0f);
                    hitInfo.hitPosition = float3(0.0f, 0.0f, 0.0f);
                    hitInfo.colour = float3(0.0f, 0.0f, 0.0f);
                    hitInfo.emissive = float3(0.0f, 0.0f, 0.0f);

                    {
                        TestSphereIntersections(currentRay, hitInfo);
                    }

                    // Missed
                    if (hitInfo.distance >= 1.#INF)
                    {
                        // color += (1.0f - a) * float3(1.0f, 1.0f, 1.0f) + a * float3(0.5f, 0.7f, 1.0f);
                        break;
                    }

                    // TODO: Fix this by adding lambertian reflection
                    currentRay.origin = hitInfo.hitPosition;
                    currentRay.direction = normalize(hitInfo.normal + RandomDirection(rngState));

                    color += hitInfo.emissive * throughput;

                    throughput *= hitInfo.colour;
                }
                return color;
            }

            float4 frag(v2f i) : SV_Target
            {
                // initialize a random number state based on frag coord and frame
                float2 fragCoord = i.uv * _ScreenParams.xy;
                uint rngState = uint(
                        uint(fragCoord.x) * uint(1973) + uint(fragCoord.y) * uint(9277) + uint(Frame) * uint(26699)) |
                    uint(1);
                float2 uv = (i.uv - 0.5f);

                Ray r = GetRayDirection(uv);
                float3 color = GetRayColor(r, rngState);
                // TODO: Test for randomness

                return float4(color, 1.0f);
            }
            ENDCG
        }
    }
}
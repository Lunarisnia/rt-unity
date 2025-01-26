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
                float smoothness;
            };

            struct Sphere
            {
                float3 albedo;
                float3 emission;
                float emissionStrength;
                float3 center;
                float radius;
                float smoothness;
            };

            StructuredBuffer<Sphere> SpheresBuffer;
            int NumOfSpheres;

            bool RaySphereIntersection(Ray r, Sphere s, inout HitInfo hitInfo)
            {
                float3 oc = s.center - r.origin;
                float a = dot(r.direction, r.direction);
                float h = -2.0 * dot(r.direction, oc);
                float c = dot(oc, oc) - s.radius * s.radius;

                float discriminant = h * h - 4.0 * a * c;
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
                hitInfo.smoothness = s.smoothness;
                return true;
            }

            struct Quad
            {
                float3 a, b, c, d;
                float smoothness;
                float3 albedo;
                float3 emission;
                float emissionStrength;
            };

            float ScalarTriple(float3 u, float3 v, float3 w)
            {
                return dot(cross(u, v), w);
            }

            bool IntersectQuad(in Quad quad, in Ray r, inout HitInfo info)
            {
                float3 a = quad.a;
                float3 b = quad.b;
                float3 c = quad.c;
                float3 d = quad.d;
                // calculate normal and flip vertices order if needed
                float3 normal = normalize(cross(c - a, c - b));
                if (dot(normal, r.direction) > 0.0f)
                {
                    normal *= -1.0f;

                    float3 temp = d;
                    d = a;
                    a = temp;

                    temp = b;
                    b = c;
                    c = temp;
                }

                float3 p = r.origin;
                float3 q = r.origin + r.direction;
                float3 pq = q - p;
                float3 pa = a - p;
                float3 pb = b - p;
                float3 pc = c - p;

                // determine which triangle to test against by testing against diagonal first
                float3 m = cross(pc, pq);
                float v = dot(pa, m);
                float3 intersectPos;
                if (v >= 0.0f)
                {
                    // test against triangle a,b,c
                    float u = -dot(pb, m);
                    if (u < 0.0f) return false;
                    float w = ScalarTriple(pq, pb, pa);
                    if (w < 0.0f) return false;
                    float denom = 1.0f / (u + v + w);
                    u *= denom;
                    v *= denom;
                    w *= denom;
                    intersectPos = u * a + v * b + w * c;
                }
                else
                {
                    float3 pd = d - p;
                    float u = dot(pd, m);
                    if (u < 0.0f) return false;
                    float w = ScalarTriple(pq, pa, pd);
                    if (w < 0.0f) return false;
                    v = -v;
                    float denom = 1.0f / (u + v + w);
                    u *= denom;
                    v *= denom;
                    w *= denom;
                    intersectPos = u * a + v * d + w * c;
                }

                float dist;
                if (abs(r.direction.x) > 0.1f)
                {
                    dist = (intersectPos.x - r.origin.x) / r.direction.x;
                }
                else if (abs(r.direction.y) > 0.1f)
                {
                    dist = (intersectPos.y - r.origin.y) / r.direction.y;
                }
                else
                {
                    dist = (intersectPos.z - r.origin.z) / r.direction.z;
                }

                if (dist > 0.001f && dist < info.distance)
                {
                    info.distance = dist;
                    info.normal = normal;
                    info.hitPosition = RayAt(r, dist);
                    info.emission = quad.emission;
                    info.emissionStrength = quad.emissionStrength;
                    info.smoothness = quad.smoothness;
                    info.albedo = quad.albedo;
                    info.frontFace = true;
                    return true;
                }

                return false;
            }

            Quad CreateQuad(float3 a, float3 b, float3 c, float3 d, float3 albedo, float3 emission, float emissionStrength, float smoothness)
            {
                Quad q;
                q.a = a;
                q.b = b;
                q.c = c;
                q.d = d;
                q.albedo = albedo;
                q.emission = emission;
                q.emissionStrength = emissionStrength;
                q.smoothness = smoothness;

                return q;
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
                h.smoothness = 0.0;

                return h;
            }

            void TestSceneIntersection(Ray r, inout HitInfo hitInfo)
            {
                // Spheres
                for (int i = 0; i < NumOfSpheres; i++)
                {
                    RaySphereIntersection(r, SpheresBuffer[i], hitInfo);
                }

                // Quad
                float depth = 40.15;
                {
                    // Backwall
                    float3 a = float3(-12.0, -12.0, depth);
                    float3 b = float3(12.0, -12.0, depth);
                    float3 c = float3(12.0, 12.0, depth);
                    float3 d = float3(-12.0, 12.0, depth);
                    Quad q1 = CreateQuad(a, b, c, d, float3(1.0, 1.0, 0.0), 0.0, 0.0, 0.0);
                    IntersectQuad(q1, r, hitInfo);
                }
                {
                    // LeftWall
                    float3 a = float3(-12.0, -12.0, depth);
                    float3 b = float3(-12.0, -12.0, depth - 30.0);
                    float3 c = float3(-12.0, 12.0, depth - 30.0);
                    float3 d = float3(-12.0, 12.0, depth);
                    Quad q1 = CreateQuad(a, b, c, d, float3(0.0, 1.0, 0.0), 0.0, 0.0, 0.0);
                    IntersectQuad(q1, r, hitInfo);
                }
                {
                    // RightWall
                    float3 a = float3(12.0, 12.0, depth);
                    float3 b = float3(12.0, 12.0, depth - 30.0);
                    float3 c = float3(12.0, -12.0, depth - 30.0);
                    float3 d = float3(12.0, -12.0, depth);
                    Quad q1 = CreateQuad(a, b, c, d, float3(0.2, 0.2, 0.1), 0.0, 0.0, 0.0);
                    IntersectQuad(q1, r, hitInfo);
                }
                {
                    // BottomWall
                    float3 a = float3(-12.0, -12.0, depth);
                    float3 b = float3(-12.0, -12.0, depth - 30.0);
                    float3 c = float3(12.0, -12.0, depth - 30.0);
                    float3 d = float3(12.0, -12.0, depth);
                    Quad q1 = CreateQuad(a, b, c, d, float3(0.4, 0.7, 0.8), 0.0, 0.0, 0.0);
                    IntersectQuad(q1, r, hitInfo);
                }
                {
                    // BottomWall
                    float3 a = float3(12.0, 12.0, depth);
                    float3 b = float3(12.0, 12.0, depth - 30.0);
                    float3 c = float3(-12.0, 12.0, depth - 30.0);
                    float3 d = float3(-12.0, 12.0, depth);
                    Quad q1 = CreateQuad(a, b, c, d, float3(0.4, 0.7, 0.8), 0.0, 0.0, 0.0);
                    IntersectQuad(q1, r, hitInfo);
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
                        // color += ((1.0f - a) * float3(0.2f, 0.1f, 0.2f) + a * float3(0.5f, 0.7f, 1.0f)) * throughput;
                        break;
                    }

                    float3 emittedLight = hitInfo.emission * hitInfo.emissionStrength;
                    color += emittedLight * throughput;

                    r.origin = hitInfo.hitPosition;
                    float3 diffuseDir = normalize(hitInfo.normal + RandomDirection(rngState));
                    float3 specularDir = normalize(reflect(r.direction, hitInfo.normal));
                    r.direction = normalize(lerp(diffuseDir, specularDir, hitInfo.smoothness));

                    throughput *= hitInfo.albedo;
                }
                return color;
            }

            float4x4 CameraLocalToWorldMatrix;
            float3 ViewParams;
            int Frame;
            int RayPerPixel;

            // TODO: add quad intersection maybe refraction
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
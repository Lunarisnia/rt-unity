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
            };

            struct Sphere
            {
                float3 albedo;
                float3 emission;
                float3 center;
                float radius;
            };

            bool RaySphereIntersection(Ray r, Sphere s, inout HitInfo hitInfo)
            {
                float3 oc = s.center - r.origin;
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

                hitInfo.hitPosition = RayAt(r, root);
                hitInfo.normal = normalize(hitInfo.hitPosition - s.center);
                hitInfo.distance = root;
                hitInfo.emission = s.emission;
                hitInfo.albedo = s.albedo;
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

                return h;
            }



            float3 GetRayColor(Ray r)
            {
                HitInfo hitInfo = CreateHitInfo();

                Sphere s;
                s.albedo = float3(1.0, 0.0, 0.0);
                s.emission = float3(0.0, 0.0, 0.0);
                s.center = float3(0.0, 0.0, 0.0);
                s.radius = 10.0;
                if (RaySphereIntersection(r, s, hitInfo))
                {
                    return s.albedo;
                }
                return float3(0.0, 0.0, 1.0);
            }

            float4x4 CameraLocalToWorldMatrix;

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = (i.uv * 2.0 - 1.0);

                float3 viewPointLocal = float3(uv, 1.0);
                float3 viewPoint = mul(CameraLocalToWorldMatrix, float4(viewPointLocal, 1.0));

                float3 origin = _WorldSpaceCameraPos;
                float3 rayDir = normalize(viewPoint - origin);

                Ray r = CreateRay(origin, rayDir);

                float3 color = GetRayColor(r);

                return float4(color, 1.0);
            }
            ENDCG
        }
    }
}
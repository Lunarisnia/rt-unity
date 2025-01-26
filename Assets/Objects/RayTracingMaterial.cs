using System;
using UnityEngine;

[Serializable]
public struct RayTracingMaterial
{
    public Color albedo;
    public Vector3 emission;
    public float emissionStrength;
    public int surfaceType;

    [Range(0.0f, 1.0f)] public float smoothness;
}
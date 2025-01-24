using UnityEngine;

public class CameraDebugging
{
    public static void DrawDot(Vector3 position)
    {
        var sphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        sphere.transform.position = position;
    }
}
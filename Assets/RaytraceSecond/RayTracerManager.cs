using UnityEngine;
using UnityEngine.Experimental.Rendering;

[ExecuteAlways]
[ImageEffectAllowedInSceneView]
public class RayTracerManager : MonoBehaviour
{
    // TODO: Render color of UV to the camera

    public Shader RayTracingShader;

    private Material rayTracingMaterial;
    private RenderTexture resultTexture;

    private void OnRenderImage(RenderTexture src, RenderTexture target)
    {
        InitMaterial();
        InitTexture("RayTracing", Screen.width, Screen.height, GraphicsFormat.R32G32B32A32_SFloat, FilterMode.Bilinear,
            0,
            false);
        UpdateCameraParams();

        Graphics.Blit(null, resultTexture, rayTracingMaterial);
        Graphics.Blit(resultTexture, target);

        resultTexture.Release();
    }

    private void InitMaterial()
    {
        rayTracingMaterial = new Material(RayTracingShader);
    }

    private void InitTexture(string name, int width, int height, GraphicsFormat format, FilterMode filterMode,
        int depthMode,
        bool useMipMaps)
    {
        var texture = new RenderTexture(width, height, depthMode);
        texture.graphicsFormat = format;
        texture.enableRandomWrite = true;
        texture.autoGenerateMips = false;
        texture.useMipMap = useMipMaps;
        texture.Create();

        texture.name = name;
        texture.wrapMode = TextureWrapMode.Clamp;
        texture.filterMode = filterMode;
        resultTexture = texture;
    }

    private void UpdateCameraParams()
    {
        rayTracingMaterial.SetMatrix("CameraLocalToWorldMatrix", transform.localToWorldMatrix);
    }
}
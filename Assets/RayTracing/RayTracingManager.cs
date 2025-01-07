using UnityEngine;

[ExecuteAlways]
[ImageEffectAllowedInSceneView]
public class RayTracingManager : MonoBehaviour
{
    // We declare our shader code to be imported
    public ComputeShader RayTracingShader;

    private Camera _camera;

    // Our Temporary Render target to draw into
    private RenderTexture _target;

    private void Awake()
    {
        _camera = GetComponent<Camera>();
    }

    private void OnRenderImage(RenderTexture source, RenderTexture dest)
    {
        if (!Application.isPlaying) Debug.Log("WTf");
        SetShaderParameters();
        // Call our custom Render
        Render(dest);
    }

    private void Render(RenderTexture dest)
    {
        Debug.Log("Name: " + name);

        // Initialize Render Target
        InitRenderTexture();

        // Set the compute shader render target to the _target
        RayTracingShader.SetTexture(0, "Result", _target);
        var threadGroupsX = Mathf.CeilToInt(Screen.width / 8.0f);
        var threadGroupsY = Mathf.CeilToInt(Screen.height / 8.0f);
        // Run the shader with the config
        RayTracingShader.Dispatch(0, threadGroupsX, threadGroupsY, 1);

        Graphics.Blit(_target, dest);
    }

    private void InitRenderTexture()
    {
        // If the render target is empty and the screen size doesn't change we stop
        if (_target != null && Screen.width == _target.width && Screen.height == _target.height) return;
        // If somehow render target is not null release the existing render target so it doesn't linger in the memory
        if (_target != null)
            _target.Release();

        // Add a new render target with the parameter to enable random write
        _target = new RenderTexture(Screen.width, Screen.height, 0, RenderTextureFormat.ARGBFloat,
            RenderTextureReadWrite.Linear)
        {
            enableRandomWrite = true
        };
        // Actually create the render texture/render target
        _target.Create();
    }

    private void SetShaderParameters()
    {
        RayTracingShader.SetMatrix("_CameraToWorld", _camera.cameraToWorldMatrix);
        RayTracingShader.SetMatrix("_CameraInverseProjection", _camera.projectionMatrix.inverse);
    }
}
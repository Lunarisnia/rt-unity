using System.Runtime.InteropServices;
using UnityEngine;

[ExecuteAlways]
[ImageEffectAllowedInSceneView]
public class RayTracingManager : MonoBehaviour
{
    // We declare our shader code to be imported
    public Shader MaterialShader;

    private Camera _camera;
    private Material _material;

    private ComputeBuffer _spheresBuffer;

    // Our Temporary Render target to draw into
    private RenderTexture _target;

    private void Awake()
    {
        _camera = GetComponent<Camera>();
    }

    private void OnRenderImage(RenderTexture source, RenderTexture dest)
    {
        if (!Application.isPlaying) Debug.Log("WTf");
        InitMaterial();
        ScanSpheres();
        SetShaderParameters();
        // Call our custom Render
        Render(dest);
    }

    private void Render(RenderTexture dest)
    {
        // Initialize Render Target
        // InitRenderTexture();

        // Run the shader and render to the screen
        Graphics.Blit(null, dest, _material);

        // Graphics.Blit(_target, dest);
    }

    private void InitMaterial()
    {
        _material = new Material(MaterialShader);
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

    // WTF: MEMORY LEAK WTF?
    private void ScanSpheres()
    {
        var sphereObjects = FindObjectsByType<RayTracedSphere>(FindObjectsSortMode.InstanceID);
        // // Debug.Log("Spheres: " + sphereObjects.Length);
        // Debug.Log(sphereObjects[1]);
        if (sphereObjects.Length < 1)
            return;
        var spheres = new Sphere[sphereObjects.Length];
        for (var i = 0; i < sphereObjects.Length; i++)
        {
            spheres[i].position = sphereObjects[i].transform.position;
            spheres[i].radius = sphereObjects[i].transform.localScale.x * 0.5f;
            spheres[i].colour = new Vector3(1.0f, 1.0f, 1.0f);
            spheres[i].material = sphereObjects[i].Material;
        }

        var stride = Marshal.SizeOf<Sphere>();
        var len = sphereObjects.Length;

        if (_spheresBuffer == null || !_spheresBuffer.IsValid() || _spheresBuffer.count != len ||
            _spheresBuffer.stride != stride)
        {
            if (_spheresBuffer != null) _spheresBuffer.Release();
            _spheresBuffer =
                new ComputeBuffer(len, stride, ComputeBufferType.Structured);
        }

        _spheresBuffer.SetData(spheres);
        _material.SetInt("NumOfSpheres", spheres.Length);
        _material.SetBuffer("SpheresBuffer", _spheresBuffer);
    }

    private void SetShaderParameters()
    {
        _material.SetMatrix("CameraLocalToWorldMatrix", _camera.cameraToWorldMatrix);
        _material.SetVector("CameraWorldSpacePosition", _camera.transform.position);
        _material.SetMatrix("CameraInverseProjection", _camera.projectionMatrix.inverse);
    }
}
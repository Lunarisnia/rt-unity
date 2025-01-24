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
    private ComputeBuffer secondSphere;

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

    private void ScanSpheres()
    {
        var sphereObjects = FindObjectsByType<RayTracedSphere>(FindObjectsSortMode.InstanceID);
        if (sphereObjects.Length < 1)
            return;
        var spheres = new Sphere[sphereObjects.Length];
        for (var i = 0; i < sphereObjects.Length; i++)
        {
            spheres[i].position = sphereObjects[i].transform.position;
            spheres[i].radius = sphereObjects[i].transform.localScale.x * 0.5f;
            spheres[i].colour = new Vector3(sphereObjects[i].Material.colour.r, sphereObjects[i].Material.colour.g,
                sphereObjects[i].Material.colour.b);
        }

        var stride = Marshal.SizeOf<Sphere>();
        var len = sphereObjects.Length;

        if (_spheresBuffer == null || !_spheresBuffer.IsValid() || _spheresBuffer.count != len ||
            _spheresBuffer.stride != stride)
        {
            if (_spheresBuffer != null)
            {
                _spheresBuffer.Release();
                _spheresBuffer = null;
            }

            _spheresBuffer =
                new ComputeBuffer(len, stride, ComputeBufferType.Structured);
        }

        _spheresBuffer.SetData(spheres);
        _material.SetInt("NumOfSpheres", spheres.Length);
        _material.SetBuffer("SpheresBuffer", _spheresBuffer);
    }

    private void SetShaderParameters()
    {
        var planeHeight = _camera.nearClipPlane * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad) * 2.0f;
        var planeWidth = planeHeight * _camera.aspect;

        _material.SetVector("ViewParams", new Vector3(planeWidth, planeHeight, _camera.nearClipPlane));
        _material.SetMatrix("CameraLocalToWorldMatrix", _camera.transform.localToWorldMatrix);
        _material.SetVector("CameraWorldSpacePosition", _camera.transform.position);
        _material.SetMatrix("CameraInverseProjection", _camera.projectionMatrix.inverse);
    }
}
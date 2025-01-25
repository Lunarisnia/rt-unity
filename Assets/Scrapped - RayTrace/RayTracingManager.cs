using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Experimental.Rendering;

[ExecuteAlways]
[ImageEffectAllowedInSceneView]
public class RayTracingManager : MonoBehaviour
{
    private const GraphicsFormat RenderFormat = GraphicsFormat.R32G32B32A32_SFloat;

    // We declare our shader code to be imported
    public Shader MaterialShader;
    public Shader AccumulateShader;
    private Material _accumulateMaterial;

    private Camera _camera;
    private Material _material;

    private ComputeBuffer _spheresBuffer;

    // Our Temporary Render target to draw into
    private RenderTexture _target;
    private ComputeBuffer secondSphere;

    private int tick;

    private void Awake()
    {
        _camera = GetComponent<Camera>();
    }

    private void OnRenderImage(RenderTexture source, RenderTexture dest)
    {
        InitMaterial();
        ScanSpheres();
        SetShaderParameters();
        // Call our custom Render
        Render(source, dest);
    }

    private void Render(RenderTexture source, RenderTexture dest)
    {
        var isSceneCam = Camera.current.name == "SceneCamera";
        if (isSceneCam)
        {
            InitRenderTexture();
            var currentFrame = RenderTexture.GetTemporary(source.width, source.height, 0, RenderFormat);
            Graphics.Blit(null, currentFrame, _material);
            Graphics.Blit(currentFrame, _target);

            // Run the shader and render to the screen
            Graphics.Blit(_target, dest);

            RenderTexture.ReleaseTemporary(currentFrame);
        }
        else
        {
            // Initialize Render Target
            InitRenderTexture();
            var prevFrameCopy =
                RenderTexture.GetTemporary(source.width, source.height, 0, RenderTextureFormat.ARGBFloat);
            Graphics.Blit(_target, prevFrameCopy);

            _accumulateMaterial.SetInt("Frame", tick);
            _accumulateMaterial.SetTexture("_PrevFrame", prevFrameCopy);
            // Graphics.Blit(null, _target, _accumulateMaterial);

            // Render the current frame
            var currentFrame =
                RenderTexture.GetTemporary(source.width, source.height, 0, RenderTextureFormat.ARGBFloat);
            Graphics.Blit(null, currentFrame, _material);

            Graphics.Blit(currentFrame, _target, _accumulateMaterial);

            // Run the shader and render to the screen
            Graphics.Blit(_target, dest);

            RenderTexture.ReleaseTemporary(prevFrameCopy);
            RenderTexture.ReleaseTemporary(currentFrame);
        }

        if (Application.isPlaying) tick += 1;
    }

    private void InitMaterial()
    {
        _material = new Material(MaterialShader);
        _accumulateMaterial = new Material(AccumulateShader);
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
            // spheres[i].position = sphereObjects[i].transform.position;
            // spheres[i].radius = sphereObjects[i].transform.localScale.x * 0.5f;
            // spheres[i].colour = new Vector3(sphereObjects[i].Material.colour.r, sphereObjects[i].Material.colour.g,
            //     sphereObjects[i].Material.colour.b);
            // spheres[i].emissive = sphereObjects[i].Material.emissive;
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
        _material.SetInt("Frame", tick);
    }
}
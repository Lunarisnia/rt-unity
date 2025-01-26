using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Experimental.Rendering;

[ExecuteAlways]
[ImageEffectAllowedInSceneView]
public class RayTracerManager : MonoBehaviour
{
    public Shader RayTracingShader;
    public Shader AccumulateShader;

    [Header("Ray Config")] [Range(0, 100)] public int RayPerPixel = 10;

    [Range(0, 100)] public int NumberOfBounces = 30;

    private ComputeBuffer _spheresBuffer;
    private Material accumulateMaterial;
    private RenderTexture copy;

    private int frame;

    private Material rayTracingMaterial;
    private RenderTexture resultTexture;

    private void OnRenderImage(RenderTexture src, RenderTexture target)
    {
        var isSceneView = Camera.current.name == "SceneCamera";
        if (isSceneView)
        {
            InitFrame();
            Graphics.Blit(null, resultTexture, rayTracingMaterial);
            Graphics.Blit(resultTexture, target);
        }
        else
        {
            InitFrame();
            var prevFrameCopy =
                RenderTexture.GetTemporary(src.width, src.height, 0, GraphicsFormat.R32G32B32A32_SFloat);
            Graphics.Blit(resultTexture, prevFrameCopy);

            var currentFrame = RenderTexture.GetTemporary(src.width, src.height, 0, GraphicsFormat.R32G32B32A32_SFloat);
            Graphics.Blit(null, currentFrame, rayTracingMaterial);

            accumulateMaterial.SetInteger("Frame", frame);
            accumulateMaterial.SetTexture("_PrevFrame", prevFrameCopy);
            Graphics.Blit(currentFrame, resultTexture, accumulateMaterial);

            Graphics.Blit(resultTexture, target);


            RenderTexture.ReleaseTemporary(currentFrame);
            RenderTexture.ReleaseTemporary(prevFrameCopy);
            RenderTexture.ReleaseTemporary(currentFrame);

            frame += Application.isPlaying ? 1 : 0;
        }
    }

    private void InitFrame()
    {
        InitMaterial();
        InitTexture("RayTracing", Screen.width, Screen.height, GraphicsFormat.R32G32B32A32_SFloat, FilterMode.Bilinear,
            0,
            false);
        InitTextureCopy("RayTracingCopy", Screen.width, Screen.height, GraphicsFormat.R32G32B32A32_SFloat,
            FilterMode.Bilinear,
            0,
            false);
        UpdateCameraParams();
        ScanSpheres();
    }

    private void InitMaterial()
    {
        rayTracingMaterial = new Material(RayTracingShader);
        accumulateMaterial = new Material(AccumulateShader);
    }

    private void InitTextureCopy(string name, int width, int height, GraphicsFormat format, FilterMode filterMode,
        int depthMode,
        bool useMipMaps)
    {
        // If the render target is empty and the screen size doesn't change we stop
        if (copy != null && Screen.width == copy.width &&
            Screen.height == copy.height) return;
        // If somehow render target is not null release the existing render target so it doesn't linger in the memory
        if (copy != null)
            copy.Release();

        var texture = new RenderTexture(width, height, depthMode);
        texture.graphicsFormat = format;
        texture.enableRandomWrite = true;
        texture.autoGenerateMips = false;
        texture.useMipMap = useMipMaps;
        texture.Create();

        texture.name = name;
        texture.wrapMode = TextureWrapMode.Clamp;
        texture.filterMode = filterMode;
        copy = texture;
    }

    private void InitTexture(string name, int width, int height, GraphicsFormat format, FilterMode filterMode,
        int depthMode,
        bool useMipMaps)
    {
        // If the render target is empty and the screen size doesn't change we stop
        if (resultTexture != null && Screen.width == resultTexture.width &&
            Screen.height == resultTexture.height) return;
        // If somehow render target is not null release the existing render target so it doesn't linger in the memory
        if (resultTexture != null)
            resultTexture.Release();

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
        var cam = Camera.current;
        var viewportHeight = cam.nearClipPlane * Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad) * 2.0f;
        var viewportWidth = viewportHeight * cam.aspect;

        rayTracingMaterial.SetVector("ViewParams", new Vector3(viewportWidth, viewportHeight, cam.nearClipPlane));
        rayTracingMaterial.SetMatrix("CameraLocalToWorldMatrix", cam.transform.localToWorldMatrix);
        rayTracingMaterial.SetInteger("Frame", frame);
        rayTracingMaterial.SetInteger("RayPerPixel", RayPerPixel);
        rayTracingMaterial.SetInteger("NumberOfBounces", NumberOfBounces);
    }

    private void ScanSpheres()
    {
        var sphereObjects = FindObjectsByType<RayTracedSphere>(FindObjectsSortMode.None);

        var spheres = new Sphere[sphereObjects.Length];
        for (var i = 0; i < sphereObjects.Length; i++)
        {
            spheres[i].center = sphereObjects[i].transform.position;
            spheres[i].radius = sphereObjects[i].transform.localScale.x * 0.5f;
            spheres[i].albedo = new Vector3(sphereObjects[i].Material.albedo.r, sphereObjects[i].Material.albedo.g,
                sphereObjects[i].Material.albedo.b);
            spheres[i].emission = sphereObjects[i].Material.emission;
            spheres[i].emissionStrength = sphereObjects[i].Material.emissionStrength;
            spheres[i].smoothness = sphereObjects[i].Material.smoothness;
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
        rayTracingMaterial.SetInt("NumOfSpheres", spheres.Length);
        rayTracingMaterial.SetBuffer("SpheresBuffer", _spheresBuffer);
    }
}
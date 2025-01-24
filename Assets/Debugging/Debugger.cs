using UnityEngine;

[ExecuteAlways]
public class Debugger : MonoBehaviour
{
    public GameObject spawned;
    private Camera cam;
    private Vector3 offset;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    private void Start()
    {
        DrawDot(Vector3.forward * 2.0f);
    }

    // Update is called once per frame
    private void Update()
    {
        cam = GetComponent<Camera>();
        Debug.Log("Local: " + cam.transform.forward);
        offset = (transform.position - spawned.transform.position).normalized;
        Vector3 cameraFront = cam.transform.localToWorldMatrix * new Vector4(1.0f, 1.0f, 3.0f, 1.0f);
        spawned.transform.position = cameraFront;
    }

    private void DrawDot(Vector3 position)
    {
        offset = position;
        var sphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        sphere.transform.position = transform.position + position;
        spawned = sphere;
    }
}
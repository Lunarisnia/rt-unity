using UnityEngine;

public class FollowingObject : MonoBehaviour
{
    public Transform TrackedObject;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    private void Start()
    {
    }

    // Update is called once per frame
    private void Update()
    {
        transform.position = TrackedObject.position + new Vector3(0.0f, 0.0f, 2.0f);
    }
}
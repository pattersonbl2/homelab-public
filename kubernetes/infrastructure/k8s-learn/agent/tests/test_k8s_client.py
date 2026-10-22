# infrastructure/k8s-learn/agent/tests/test_k8s_client.py
from unittest.mock import MagicMock, patch
import pytest


def make_pod(name, phase, restarts=0):
    pod = MagicMock()
    pod.metadata.name = name
    pod.status.phase = phase
    cs = MagicMock()
    cs.restart_count = restarts
    pod.status.container_statuses = [cs]
    return pod


def make_deployment(name, ready, desired):
    d = MagicMock()
    d.metadata.name = name
    d.status.ready_replicas = ready
    d.spec.replicas = desired
    return d


def make_service(name, svc_type, port):
    s = MagicMock()
    s.metadata.name = name
    s.spec.type = svc_type
    p = MagicMock()
    p.port = port
    s.spec.ports = [p]
    return s


def make_event(reason, message):
    e = MagicMock()
    e.type = "Warning"
    e.reason = reason
    e.message = message
    e.last_timestamp = "2026-04-15T00:00:00Z"
    e.event_time = None
    return e


def test_fetch_namespace_state_formats_pods():
    from k8s_client import _fetch_namespace_state
    with patch("k8s_client.client.CoreV1Api") as mock_v1, \
         patch("k8s_client.client.AppsV1Api") as mock_apps, \
         patch("k8s_client.client.NetworkingV1Api") as mock_net:
        mock_v1.return_value.list_namespaced_pod.return_value.items = [
            make_pod("hello", "Running", 2)
        ]
        mock_v1.return_value.list_namespaced_service.return_value.items = []
        mock_v1.return_value.list_namespaced_event.return_value.items = []
        mock_apps.return_value.list_namespaced_deployment.return_value.items = []
        mock_net.return_value.list_namespaced_ingress.return_value.items = []

        result = _fetch_namespace_state("learn-test")

    assert "Pod: hello (Running, 2 restarts)" in result
    assert "Namespace: learn-test" in result


def test_fetch_namespace_state_includes_warnings():
    from k8s_client import _fetch_namespace_state
    with patch("k8s_client.client.CoreV1Api") as mock_v1, \
         patch("k8s_client.client.AppsV1Api") as mock_apps, \
         patch("k8s_client.client.NetworkingV1Api") as mock_net:
        mock_v1.return_value.list_namespaced_pod.return_value.items = []
        mock_v1.return_value.list_namespaced_service.return_value.items = []
        mock_v1.return_value.list_namespaced_event.return_value.items = [
            make_event("FailedScheduling", "0/6 nodes available: insufficient CPU")
        ]
        mock_apps.return_value.list_namespaced_deployment.return_value.items = []
        mock_net.return_value.list_namespaced_ingress.return_value.items = []

        result = _fetch_namespace_state("learn-test")

    assert "FailedScheduling" in result
    assert "insufficient CPU" in result


def test_fetch_namespace_state_returns_empty_when_no_resources():
    from k8s_client import _fetch_namespace_state
    with patch("k8s_client.client.CoreV1Api") as mock_v1, \
         patch("k8s_client.client.AppsV1Api") as mock_apps, \
         patch("k8s_client.client.NetworkingV1Api") as mock_net:
        mock_v1.return_value.list_namespaced_pod.return_value.items = []
        mock_v1.return_value.list_namespaced_service.return_value.items = []
        mock_v1.return_value.list_namespaced_event.return_value.items = []
        mock_apps.return_value.list_namespaced_deployment.return_value.items = []
        mock_net.return_value.list_namespaced_ingress.return_value.items = []

        result = _fetch_namespace_state("learn-test")

    assert result == ""

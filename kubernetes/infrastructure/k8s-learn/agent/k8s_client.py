# infrastructure/k8s-learn/agent/k8s_client.py
import asyncio
from concurrent.futures import ThreadPoolExecutor
from kubernetes import client, config

_executor = ThreadPoolExecutor(max_workers=4)


def _load_k8s_config():
    try:
        config.load_incluster_config()
    except config.ConfigException:
        try:
            config.load_kube_config()
        except Exception:
            pass


_load_k8s_config()


def _fetch_namespace_state(namespace: str) -> str:
    v1 = client.CoreV1Api()
    apps_v1 = client.AppsV1Api()
    networking_v1 = client.NetworkingV1Api()

    lines = [f"Namespace: {namespace}"]

    try:
        for p in v1.list_namespaced_pod(namespace).items:
            phase = p.status.phase or "Unknown"
            restarts = sum(cs.restart_count for cs in (p.status.container_statuses or []))
            lines.append(f"Pod: {p.metadata.name} ({phase}, {restarts} restarts)")
    except Exception:
        pass

    try:
        for d in apps_v1.list_namespaced_deployment(namespace).items:
            ready = d.status.ready_replicas or 0
            desired = d.spec.replicas or 0
            lines.append(f"Deployment: {d.metadata.name} ({ready}/{desired} ready)")
    except Exception:
        pass

    try:
        for s in v1.list_namespaced_service(namespace).items:
            if s.metadata.name == "kubernetes":
                continue
            port = s.spec.ports[0].port if s.spec.ports else "?"
            lines.append(f"Service: {s.metadata.name} ({s.spec.type}:{port})")
    except Exception:
        pass

    try:
        for i in networking_v1.list_namespaced_ingress(namespace).items:
            host = i.spec.rules[0].host if i.spec.rules else "?"
            lines.append(f"Ingress: {i.metadata.name} ({host})")
    except Exception:
        pass

    try:
        events = v1.list_namespaced_event(namespace).items
        warnings = [e for e in events if e.type == "Warning"]
        warnings.sort(key=lambda e: e.last_timestamp or e.event_time or "", reverse=True)
        for e in warnings[:5]:
            lines.append(f"Warning: {e.reason} - {e.message}")
    except Exception:
        pass

    return "\n".join(lines) if len(lines) > 1 else ""


async def get_namespace_state(namespace: str) -> str:
    if not namespace:
        return ""
    loop = asyncio.get_event_loop()
    try:
        return await asyncio.wait_for(
            loop.run_in_executor(_executor, _fetch_namespace_state, namespace),
            timeout=10.0
        )
    except Exception:
        return ""

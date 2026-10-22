.PHONY: wg wg-stop kube argo argo-stop dns

KUBECONFIG_PATH := $(HOME)/.kube/homelab-k3s.yaml
ARGO_PORT := 8080

## Start WireGuard tunnel to homelab
wg:
	@if sudo wg show homelab >/dev/null 2>&1; then \
		echo "WireGuard tunnel already active"; \
	else \
		sudo wg-quick up homelab; \
		echo "WireGuard tunnel started"; \
	fi

## Stop WireGuard tunnel
wg-stop:
	@sudo wg-quick down homelab 2>/dev/null && echo "WireGuard tunnel stopped" || echo "No WireGuard tunnel running"

## Connect to K3s (starts WireGuard if needed, then verifies)
kube:
	@$(MAKE) --no-print-directory wg
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get nodes

## Start ArgoCD port-forward and log in CLI
argo:
	@$(MAKE) --no-print-directory wg
	@if lsof -i :$(ARGO_PORT) >/dev/null 2>&1; then \
		echo "ArgoCD port-forward already running on port $(ARGO_PORT)"; \
	else \
		KUBECONFIG=$(KUBECONFIG_PATH) kubectl port-forward svc/argocd-server -n argocd $(ARGO_PORT):443 >/dev/null 2>&1 & \
		sleep 2; \
		echo "ArgoCD port-forward started on localhost:$(ARGO_PORT)"; \
	fi
	@argocd login localhost:$(ARGO_PORT) --username admin \
		--password $$(KUBECONFIG=$(KUBECONFIG_PATH) kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
		--insecure --plaintext

## Stop ArgoCD port-forward
argo-stop:
	@pkill -f "kubectl port-forward svc/argocd-server" 2>/dev/null && echo "ArgoCD port-forward stopped" || echo "No ArgoCD port-forward running"

## Update local DNS entries from Traefik labels + K3s inventory
dns:
	@$(CURDIR)/scripts/update-local-dns.sh

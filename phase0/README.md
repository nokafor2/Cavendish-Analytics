# Phase 0 — Reverse Proxy Foundations (k3s)

Manual k3s stack built before EKS provisioning. Each component maps directly to an EKS equivalent — see `docs/phase0-to-eks-mapping.md`.

## Prerequisites

- EC2 instance (t3.small minimum) with ports 80, 443, 6443 open
- FreeDNS account (Afraid.org) for subdomain registration
- kubectl, helm CLI installed locally

## Day 1 — Nginx Ingress + DNS

```bash
# Install k3s with Traefik disabled
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -

# Install Nginx Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# Deploy placeholder service
kubectl apply -f manifests/http-echo-deployment.yaml
kubectl apply -f manifests/http-echo-ingress.yaml

# Register FreeDNS A record: api.yourname.mooo.com → EC2 public IP
# Verify: curl http://api.yourname.mooo.com
```

**Deliverable P0-D1:** HTTP 200 from cluster via Ingress.

## Day 2 — cert-manager + HTTPS

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

kubectl apply -f manifests/cluster-issuer.yaml
kubectl apply -f manifests/http-echo-ingress-tls.yaml

# Watch challenge: kubectl get challenges -n default -w
# Verify: curl -I https://api.yourname.mooo.com
```

**Deliverable P0-D2:** Certificate Ready, HTTPS 200.

## Day 3 — IP Restriction + Decommission

```bash
kubectl apply -f manifests/http-echo-ingress-whitelist.yaml
# Test from non-whitelisted IP → 403
# Delete ingress → 404; restore → 200
```

**Deliverable P0-D3:** Whitelist enforced, decommission pattern verified.

Record curl output in `docs/phase0-demo.txt`.

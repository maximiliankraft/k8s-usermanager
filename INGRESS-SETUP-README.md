# Nginx Ingress Controller Setup for Kind

## Prerequisites

- Kind cluster must be created with the port mappings in `kind-config.yaml`
- The cluster should have the control plane with ports 80 and 443 exposed

## Installation Steps

### 1. Create Kind Cluster with Proper Configuration

```bash
sudo kind create cluster --config kind-config.yaml --name kind
```

### 2. Install Nginx Ingress Controller

**Important:** This must be done AFTER creating the cluster, not during cluster creation.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

### 3. Wait for Ingress Controller to be Ready

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

### 4. Verify Installation

```bash
# Check if ingress controller is running
kubectl get pods -n ingress-nginx

# Check if IngressClass is created
kubectl get ingressclass
```

You should see output showing:
- A running `ingress-nginx-controller` pod
- An IngressClass named `nginx` (marked as default)

## Testing

Create a test ingress to verify it works:

```bash
# Create a test deployment
kubectl create deployment hello --image=gcr.io/google-samples/hello-app:1.0
kubectl expose deployment hello --port=8080

# Create test ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: hello.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello
            port:
              number: 8080
EOF

# Test it
curl http://hello.localhost
```

## Troubleshooting

### Ingress not working

1. Check if controller is running:
   ```bash
   kubectl get pods -n ingress-nginx
   ```

2. Check ingress status:
   ```bash
   kubectl get ingress -A
   ```

3. Check controller logs:
   ```bash
   kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
   ```

### Port conflicts

If ports 80/443 are already in use:
```bash
sudo lsof -i :80
sudo lsof -i :443
```

## Cleanup

To remove the ingress controller:

```bash
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

## Notes

- The nginx ingress controller is **required** for user ingress resources to work
- This setup is specific to Kind clusters
- For production clusters, use the appropriate ingress controller for your environment
- The `kind-config.yaml` ensures ports 80 and 443 are mapped from the container to the host

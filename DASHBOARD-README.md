# Kubernetes Dashboard Deployment Guide

This guide will help you deploy the Kubernetes Dashboard on your k3s cluster.

## Files Overview

- `kubernetes-dashboard.yaml` - Main dashboard deployment with all necessary components
- `dashboard-adminuser.yaml` - Admin user ServiceAccount with cluster-admin privileges

## Deployment Steps

### 1. Deploy the Kubernetes Dashboard

```bash
kubectl apply -f kubernetes-dashboard.yaml
```

This will create:
- A new namespace `kubernetes-dashboard`
- Dashboard deployment and service
- Metrics scraper deployment
- Necessary RBAC configurations

### 2. Create Admin User

```bash
kubectl apply -f dashboard-adminuser.yaml
```

This creates an admin user with cluster-admin privileges for accessing the dashboard.

### 3. Get Access Token

To log into the dashboard, you'll need a bearer token. Get it with:

```bash
kubectl -n kubernetes-dashboard create token admin-user
```

Copy the token output - you'll need it to log into the dashboard.

**Note:** The token created with `create token` has a default expiration time (typically 1 hour). For a long-lived token, you can create a secret:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
EOF
```

Then retrieve it with:
```bash
kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath={".data.token"} | base64 -d
```

### 4. Access the Dashboard

#### Option A: kubectl proxy (Recommended for local access)

Start the proxy:
```bash
kubectl proxy
```

Access the dashboard at:
```
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

#### Option B: Port Forward

Forward the dashboard port:
```bash
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443
```

Access the dashboard at:
```
https://localhost:8443
```

**Note:** You'll get a certificate warning in your browser - this is expected with self-signed certificates. Accept and proceed.

#### Option C: NodePort Service (For external access)

Edit the service to use NodePort:
```bash
kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{"spec":{"type":"NodePort"}}'
```

Get the NodePort:
```bash
kubectl get svc kubernetes-dashboard -n kubernetes-dashboard
```

Access using: `https://<node-ip>:<node-port>`

## Login

1. Navigate to the dashboard URL
2. Select "Token" authentication method
3. Paste the token you obtained earlier
4. Click "Sign In"

## Verify Deployment

Check if all pods are running:
```bash
kubectl get pods -n kubernetes-dashboard
```

Check services:
```bash
kubectl get svc -n kubernetes-dashboard
```

## Security Notes

⚠️ **Important:** The admin-user has cluster-admin privileges, which grants full access to your cluster. In production:
- Consider creating users with limited permissions
- Use namespace-specific roles instead of cluster-admin
- Implement network policies to restrict dashboard access
- Consider using an ingress controller with proper TLS certificates

## Troubleshooting

### Pods not starting
```bash
kubectl describe pods -n kubernetes-dashboard
kubectl logs -n kubernetes-dashboard <pod-name>
```

### Cannot access dashboard
- Ensure kubectl proxy or port-forward is running
- Check firewall rules if using NodePort
- Verify the service is running: `kubectl get svc -n kubernetes-dashboard`

## Cleanup

To remove the dashboard:
```bash
kubectl delete -f dashboard-adminuser.yaml
kubectl delete -f kubernetes-dashboard.yaml
```

Or delete the entire namespace:
```bash
kubectl delete namespace kubernetes-dashboard
```

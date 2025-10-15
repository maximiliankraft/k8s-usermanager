# Kubernetes Dashboard Deployment Guide

## Installation Steps

### 1. Install Kubernetes Dashboard
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### 2. Create Admin User
```bash
kubectl apply -f dashboard-admin-user.yaml
```

### 3. Get Access Token
```bash
kubectl -n kubernetes-dashboard create token admin-user --duration=87600h
```

Save this token - you'll need it to log into the dashboard!

### 4. Access the Dashboard

#### Option A: Using kubectl proxy (from your local machine)
```bash
kubectl proxy
```
Then access: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

#### Option B: Using kubectl proxy on the server (accessible from other machines)
```bash
kubectl proxy --address='0.0.0.0' --accept-hosts='.*'
```
Then access: http://<server-ip>:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

#### Option C: Port Forward (more secure)
```bash
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard 8443:443
```
Then access: https://localhost:8443

### 5. Login
When prompted, select "Token" and paste the token from step 3.

## Cleanup
To remove the dashboard:
```bash
kubectl delete -f dashboard-admin-user.yaml
kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

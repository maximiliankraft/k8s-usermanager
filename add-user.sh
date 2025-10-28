#!/bin/bash

# Kubernetes User Creation Script with Ingress Setup
# Usage: ./add-user-with-ingress.sh <username> <domain> [namespace] [role] [cert-name]

set -e

# Configuration
USERNAME="${1}"
BASE_DOMAIN="${2}"
NAMESPACE="${3:-${USERNAME}}"  # Default namespace to username
ROLE="${4:-developer}"
CERT_NAME="${5:-wildcard-cert}"  # Name of the wildcard TLS secret
CERT_DIR="./k8s-users"
DAYS_VALID=365

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate input
if [ -z "$USERNAME" ] || [ -z "$BASE_DOMAIN" ]; then
    print_error "Username and domain are required!"
    echo "Usage: $0 <username> <domain> [namespace] [role] [cert-name]"
    echo "Example: $0 john example.com john-namespace developer wildcard-cert"
    exit 1
fi

# Construct user subdomain
USER_SUBDOMAIN="${USERNAME}.${BASE_DOMAIN}"

print_info "Creating user: $USERNAME"
print_info "Namespace: $NAMESPACE"
print_info "Role: $ROLE"
print_info "User subdomain: $USER_SUBDOMAIN"

# Get cluster information
CLUSTER_NAME=$(kubectl config view -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Fix server URL if it's using 0.0.0.0 (replace with 127.0.0.1)
CLUSTER_SERVER=$(echo "$CLUSTER_SERVER" | sed 's|0\.0\.0\.0|127.0.0.1|g')

echo "Cluster Server: $CLUSTER_SERVER"

if [ -z "$CLUSTER_NAME" ] || [ -z "$CLUSTER_SERVER" ]; then
    print_error "Could not retrieve cluster information. Make sure kubectl is configured."
    exit 1
fi

print_info "Cluster: $CLUSTER_NAME ($CLUSTER_SERVER)"

# Create directory for certificates
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# 1. Generate private key
print_info "Generating private key..."
openssl genrsa -out "${USERNAME}.key" 2048

# 2. Create certificate signing request
print_info "Creating certificate signing request..."
openssl req -new \
    -key "${USERNAME}.key" \
    -out "${USERNAME}.csr" \
    -subj "/CN=${USERNAME}/O=${ROLE}"

# 3. Encode CSR for Kubernetes
CSR_BASE64=$(cat "${USERNAME}.csr" | base64 | tr -d '\n')

# 4. Create Kubernetes CSR object
print_info "Submitting CSR to Kubernetes..."
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USERNAME}
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: $((DAYS_VALID * 24 * 3600))
  usages:
  - client auth
EOF

# 5. Approve the CSR
print_info "Approving certificate..."
kubectl certificate approve "${USERNAME}"

# 6. Wait for certificate to be issued
print_info "Waiting for certificate to be issued..."
sleep 2

# 7. Retrieve the certificate
kubectl get csr "${USERNAME}" -o jsonpath='{.status.certificate}' | base64 -d > "${USERNAME}.crt"

if [ ! -s "${USERNAME}.crt" ]; then
    print_error "Failed to retrieve certificate"
    exit 1
fi

print_info "Certificate issued successfully"

# 8. Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  print_warning "Namespace $NAMESPACE does not exist. Creating it..."
  kubectl create namespace "$NAMESPACE"
  # wait for namespace to be available (avoid race conditions)
  for i in {1..10}; do
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    print_error "Failed to create namespace $NAMESPACE"
    exit 1
  fi
fi

# 9. Check if ingress class exists
INGRESS_CLASS=$(kubectl get ingressclass -o=jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "nginx")
print_info "Using ingress class: $INGRESS_CLASS"

# 10. Create Role (or use existing ClusterRole)
print_info "Setting up RBAC permissions..."

case $ROLE in
    "admin")
        CLUSTER_ROLE="admin"
        ;;
    "edit")
        CLUSTER_ROLE="edit"
        ;;
    "view")
        CLUSTER_ROLE="view"
        ;;
    "developer")
        # Create custom developer role with restricted ingress permissions
        kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: ${NAMESPACE}
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/portforward", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
        CLUSTER_ROLE="developer"
        ;;
    *)
        print_warning "Unknown role: $ROLE. Using 'view' role."
        CLUSTER_ROLE="view"
        ;;
esac

# 11. Create RoleBinding
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${USERNAME}-binding
  namespace: ${NAMESPACE}
subjects:
- kind: User
  name: ${USERNAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${CLUSTER_ROLE}
  apiGroup: rbac.authorization.k8s.io
EOF

# 12. Check if wildcard certificate exists or needs to be created
if ! kubectl get secret "$CERT_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    print_warning "Certificate $CERT_NAME not found in namespace $NAMESPACE"
    
    # Check if it exists in other namespace to copy (usually cert-manager or kube-system)
  if kubectl get namespace cert-manager >/dev/null 2>&1 && kubectl get secret "$CERT_NAME" -n cert-manager >/dev/null 2>&1; then
        print_info "Found certificate in cert-manager namespace, copying..."
        kubectl get secret "$CERT_NAME" -n cert-manager -o yaml | \
            sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
            kubectl apply -f -
  elif kubectl get namespace kube-system >/dev/null 2>&1 && kubectl get secret "$CERT_NAME" -n kube-system >/dev/null 2>&1; then
        print_info "Found certificate in kube-system namespace, copying..."
        kubectl get secret "$CERT_NAME" -n kube-system -o yaml | \
            sed "s/namespace: kube-system/namespace: $NAMESPACE/" | \
            kubectl apply -f -
    else
        print_warning "Wildcard certificate $CERT_NAME not found in common namespaces."
        print_warning "You may need to create or copy the certificate manually."
        print_warning "Proceeding with setup, but ingress TLS configuration may fail."
    fi
fi


# 13. Provide a practical example ingress template with nginx service
print_info "Creating practical nginx example for ${USER_SUBDOMAIN}..."
cat <<EOF > "${USERNAME}-nginx-example.yaml"
# ConfigMap with custom index.html that shows user info
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${USERNAME}-nginx-config
  namespace: ${NAMESPACE}
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
      <title>Welcome to ${USERNAME}'s Service</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          line-height: 1.6;
          margin: 0;
          padding: 30px;
          background-color: #f5f5f5;
        }
        .container {
          max-width: 800px;
          margin: 0 auto;
          background-color: white;
          padding: 30px;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
          color: #2c3e50;
          border-bottom: 1px solid #eee;
          padding-bottom: 10px;
        }
        .info-box {
          background-color: #f8f9fa;
          border-left: 4px solid #3498db;
          padding: 15px;
          margin: 20px 0;
        }
        .success {
          color: #27ae60;
          font-weight: bold;
        }
        code {
          background-color: #f8f9fa;
          padding: 2px 5px;
          border-radius: 3px;
          font-family: monospace;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Welcome to ${USERNAME}'s Service</h1>
        
        <p>Your Kubernetes service is <span class="success">running successfully!</span></p>
        
        <div class="info-box">
          <h3>Account Information</h3>
          <p><strong>Username:</strong> ${USERNAME}</p>
          <p><strong>Namespace:</strong> ${NAMESPACE}</p>
          <p><strong>Subdomain:</strong> ${USER_SUBDOMAIN}</p>
        </div>
        
        <h3>Getting Started</h3>
        <p>You can deploy your own applications in this namespace and expose them via your subdomain.</p>
        <p>For example, to deploy a service called "myapp":</p>
        <pre><code>kubectl create deployment myapp --image=your-image:tag</code></pre>
        <pre><code>kubectl expose deployment myapp --port=80</code></pre>
        
        <p>Then create an ingress.yaml file for it:</p>
        <pre><code>
          apiVersion: networking.k8s.io/v1
          kind: Ingress
          metadata:
            name: myapp-ingress
            namespace: ${NAMESPACE}
          spec:
            ingressClassName: ${INGRESS_CLASS}
            tls:
            - hosts:
              - ${USER_SUBDOMAIN}
              secretName: ${CERT_NAME}
            rules:
            - host: ${USER_SUBDOMAIN}
              http:
                paths:
                - path: /myapp
                  pathType: Prefix
                  backend:
                    service:
                      name: myapp
                      port:
                        number: 80

        </code></pre>
        Then apply it with: 
        <pre><code>kubectl apply -f ingress.yaml</code></pre>
      </div>
    </body>
    </html>

---
# Deployment for the nginx server
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${USERNAME}-nginx
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: ${USERNAME}-nginx
  replicas: 1
  template:
    metadata:
      labels:
        app: ${USERNAME}-nginx
    spec:
      containers:
      - name: nginx
        image: nginx:stable-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /usr/share/nginx/html/index.html
          subPath: index.html
      volumes:
      - name: nginx-config
        configMap:
          name: ${USERNAME}-nginx-config

---
# Service to expose the nginx server
apiVersion: v1
kind: Service
metadata:
  name: ${USERNAME}-nginx
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${USERNAME}-nginx
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP

---
# Ingress to provide external access via subdomain
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${USERNAME}-ingress
  namespace: ${NAMESPACE}
spec:
  ingressClassName: ${INGRESS_CLASS}
  tls:
  - hosts:
    - ${USER_SUBDOMAIN}
    secretName: ${CERT_NAME}
  rules:
  - host: ${USER_SUBDOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${USERNAME}-nginx
            port:
              number: 80
EOF
print_info "Practical nginx example saved to $CERT_DIR/${USERNAME}-nginx-example.yaml"

# 15. Create kubeconfig file
print_info "Creating kubeconfig file..."

KUBECONFIG_FILE="${USERNAME}-kubeconfig.yaml"

cat > "$KUBECONFIG_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
    user: ${USERNAME}
  name: ${USERNAME}@${CLUSTER_NAME}
current-context: ${USERNAME}@${CLUSTER_NAME}
users:
- name: ${USERNAME}
  user:
    client-certificate-data: $(cat ${USERNAME}.crt | base64 | tr -d '\n')
    client-key-data: $(cat ${USERNAME}.key | base64 | tr -d '\n')
EOF

# 16. Test the configuration
print_info "Testing the configuration..."
if kubectl --kubeconfig="$KUBECONFIG_FILE" auth can-i get pods -n "$NAMESPACE" &> /dev/null; then
    print_info "Configuration test passed!"
else
    print_warning "Configuration test failed. User may not have necessary permissions."
fi

# 17. Create quick-start example deployment and service
cat > "${USERNAME}-example-app.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: example-app
  replicas: 1
  template:
    metadata:
      labels:
        app: example-app
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: example-app
  namespace: ${NAMESPACE}
spec:
  selector:
    app: example-app
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-app
  namespace: ${NAMESPACE}
spec:
  ingressClassName: ${INGRESS_CLASS}
  tls:
  - hosts:
    - ${USER_SUBDOMAIN}
    secretName: ${CERT_NAME}
  rules:
  - host: ${USER_SUBDOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-app
            port:
              number: 80
EOF

print_info "Example application configuration saved to $CERT_DIR/${USERNAME}-example-app.yaml"
print_info "To deploy the example app, run: kubectl apply -f $CERT_DIR/${USERNAME}-example-app.yaml"

# Summary
cd ..
print_info "=========================================="
print_info "User creation with ingress completed successfully!"
print_info "=========================================="
echo ""
echo "User: $USERNAME"
echo "Namespace: $NAMESPACE"
echo "Role: $ROLE"
echo "Subdomain: $USER_SUBDOMAIN"
echo "Kubeconfig file: $CERT_DIR/$KUBECONFIG_FILE"
echo ""
echo "To use this configuration:"
echo "  export KUBECONFIG=$CERT_DIR/$KUBECONFIG_FILE"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "Example files created:"
echo "  - $CERT_DIR/${USERNAME}-nginx-example.yaml (Practical nginx example with custom webpage)"
echo "  - $CERT_DIR/${USERNAME}-example-app.yaml (Basic example with deployment, service, and ingress)"
echo ""
echo "If you want to deploy the nginx example with user information:"
echo "  kubectl apply -f $CERT_DIR/${USERNAME}-nginx-example.yaml"
echo ""
echo "The user will then be able to access their application at: https://$USER_SUBDOMAIN"
echo ""
print_info "Certificate expires in $DAYS_VALID days"
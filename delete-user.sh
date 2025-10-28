#!/bin/bash

# Script to remove a user from the Kubernetes cluster
# Usage: ./delete-user.sh <username>

# Check if a username was provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <username>"
  echo "Example: $0 test01"
  exit 1
fi

USERNAME=$1
echo "Removing user: $USERNAME"

# Function to check if a resource exists before attempting to delete it
resource_exists() {
  local resource_type=$1
  local resource_name=$2
  local namespace=$3
  
  if [ -z "$namespace" ]; then
    kubectl get "$resource_type" "$resource_name" &>/dev/null
  else
    kubectl get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null
  fi
  
  return $?
}

# Delete ingress resources (if any)
if resource_exists namespace "$USERNAME"; then
  echo "Deleting ingresses in namespace $USERNAME..."
  kubectl delete ingress --all -n "$USERNAME" 2>/dev/null || true
fi

# Delete all deployments, services and other resources in the user's namespace
if resource_exists namespace "$USERNAME"; then
  echo "Deleting all resources in namespace $USERNAME..."
  kubectl delete all --all -n "$USERNAME" 2>/dev/null || true
  
  # Wait a moment for resources to be deleted
  echo "Waiting for resources to be deleted..."
  sleep 5
fi

# Delete the user's namespace
if resource_exists namespace "$USERNAME"; then
  echo "Deleting namespace $USERNAME..."
  kubectl delete namespace "$USERNAME"
fi

# Delete the user's ClusterRoleBinding
if resource_exists clusterrolebinding "$USERNAME-binding"; then
  echo "Deleting cluster role binding $USERNAME-binding..."
  kubectl delete clusterrolebinding "$USERNAME-binding"
fi

# Delete the developer ClusterRole if it's not being used by other users
# Note: We're keeping the developer role as it might be used by other users
# If you want to remove it, uncomment the following lines:
# echo "Checking if developer role is used by other bindings..."
# BINDINGS=$(kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name == "developer") | .metadata.name')
# if [ -z "$BINDINGS" ]; then
#   echo "Deleting unused developer role..."
#   kubectl delete clusterrole developer
# fi

# Remove the user's certificate files
echo "Removing certificate files..."
rm -f "k8s-users/$USERNAME.key"
rm -f "k8s-users/$USERNAME.csr"
rm -f "k8s-users/$USERNAME.crt"
rm -f "k8s-users/$USERNAME-kubeconfig.yaml"
rm -f "k8s-users/$USERNAME-example-app.yaml"
rm -f "k8s-users/$USERNAME-nginx-example.yaml"

# Delete the user from Kubernetes
echo "Revoking user certificate..."
kubectl delete csr "$USERNAME" 2>/dev/null || true

echo "User $USERNAME has been successfully removed from the cluster!"
echo "All associated resources, certificates, and RBAC configurations have been deleted."
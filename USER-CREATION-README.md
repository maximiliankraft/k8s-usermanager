# K8s user creation

## Prerequisites

Before creating users, ensure the nginx ingress controller is installed. See [INGRESS-SETUP-README.md](./INGRESS-SETUP-README.md) for instructions.

## Creating a User

Run `sh ./add-user.sh <name> <domain>`

To use this configuration:
```sh
  export KUBECONFIG=<k8s-config-file>
  kubectl get pods -n $NAMESPACE"
```


The following file got created:
```sh
$CERT_DIR/${USERNAME}-nginx-example.yaml
```

Apply it with: ${USERNAME}-nginx-example.yaml

The user will then be able to access their application at: `https://$USER_SUBDOMAIN`

## Deletion

Delete an existing user with:

```sh
sh ./delete-user.sh <name>
```
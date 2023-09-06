#!/bin/bash
set -e

# First tear down Applications
#kubectl delete provisioners.karpenter.sh --all # this is ok if no addons are deployed on Karpenter.
kubectl delete application bootstrap-workloads -n argocd || (echo "error deleting bootstrap-workloads application")
kubectl delete application -l argocd.argoproj.io/application-set-name=eks-blueprints-workloads -n argocd || (echo "error deleting workloads application";)

#kubectl delete application ecsdemo -n argocd || (echo "error deleting ecsdemo application")

#namespace geordie was stuck
#kubectl get applications  -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}' | xargs -I {} kubectl patch application {}  --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
kubectl get ingress  -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}' | xargs -I {} kubectl patch ingress {}  --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'

echo "Tear Down Applications OK"

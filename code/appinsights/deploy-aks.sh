#!/bin/bash

# Script de deploy no AKS
# Uso: ./deploy-aks.sh [namespace]

set -e

NAMESPACE=${1:-"northwind-demo"}

echo "🚀 Iniciando deploy no AKS..."
echo "📍 Namespace: $NAMESPACE"

# Verificar se kubectl está configurado
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Erro: kubectl não está configurado ou cluster não acessível"
    exit 1
fi

# Aplicar manifests na ordem correta
echo "1️⃣  Criando namespace..."
kubectl apply -f k8s/namespace.yaml

echo "2️⃣  Aplicando configurações..."
kubectl apply -f k8s/configmap.yaml

echo "3️⃣  Deploying backend..."
kubectl apply -f k8s/backend-deployment.yaml

echo "4️⃣  Deploying frontend..."
kubectl apply -f k8s/frontend-deployment.yaml

echo "5️⃣  Deploying load generator..."
kubectl apply -f k8s/loadgen-deployment.yaml

echo "6️⃣  Configurando ingress e HPA..."
kubectl apply -f k8s/ingress-hpa.yaml

echo "7️⃣  Aplicando políticas..."
kubectl apply -f k8s/policies.yaml

echo "⏳ Aguardando pods ficarem prontos..."
kubectl wait --for=condition=ready pod -l app=northwind-backend -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=ready pod -l app=northwind-frontend -n $NAMESPACE --timeout=300s

echo "✅ Deploy concluído!"
echo ""
echo "📋 Status dos recursos:"
kubectl get pods,services,ingress -n $NAMESPACE

echo ""
echo "🔍 Para monitorar:"
echo "   kubectl logs -f deployment/northwind-backend -n $NAMESPACE"
echo "   kubectl logs -f deployment/northwind-frontend -n $NAMESPACE"
echo ""
echo "🌐 Para acessar:"
FRONTEND_IP=$(kubectl get service northwind-frontend-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending...")
LOADGEN_IP=$(kubectl get service northwind-loadgen-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending...")

echo "   Frontend: http://$FRONTEND_IP"
echo "   Load Generator UI: http://$LOADGEN_IP:8089"
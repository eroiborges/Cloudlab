#!/bin/bash
# Build and deployment script for EntraID Demo App

set -e

# Configuration
IMAGE_NAME="entraiddemo"
IMAGE_TAG="v1"
REGISTRY="docker.io"  # Change to your registry
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "🚀 Building and deploying EntraID Demo App..."

# Build Docker image
echo "📦 Building Docker image: ${FULL_IMAGE_NAME}"
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE_NAME}

echo "✅ Docker image built successfully!"

# Optional: Push to registry (uncomment when ready)
# echo "📤 Pushing image to registry..."
# docker push ${FULL_IMAGE_NAME}
# echo "✅ Image pushed to registry!"

# Deploy to Kubernetes
echo "☸️  Deploying to Kubernetes..."

# Apply ConfigMap and Secrets
echo "📋 Applying ConfigMap and Secrets..."
kubectl apply -f k8s/configmap.yaml

# Apply Deployment
echo "🚀 Applying Deployment..."
kubectl apply -f k8s/deployment.yaml

# Wait for rollout
echo "⏳ Waiting for deployment to complete..."
kubectl rollout status deployment/entraiddemo-deployment --timeout=300s

# Get service info
echo "📊 Deployment Status:"
kubectl get pods -l app=entraiddemo
kubectl get services -l app=entraiddemo
kubectl get ingress -l app=entraiddemo

echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "🔗 Access methods:"
echo "   - Port Forward: kubectl port-forward service/entraiddemo-service 8080:80"
echo "   - Ingress: https://your-domain.com (if configured)"
echo ""
echo "📋 Useful commands:"
echo "   - View logs: kubectl logs -l app=entraiddemo --tail=50 -f"
echo "   - Scale: kubectl scale deployment entraiddemo-deployment --replicas=3"
echo "   - Delete: kubectl delete -f k8s/"
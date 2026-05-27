# PowerShell script para Windows
# Script de build e deploy das imagens Docker
# Uso: .\build-and-deploy.ps1 [your-acr-name] [tag]

param(
    [string]$AcrName = "your-acr",
    [string]$Tag = "latest"
)

Write-Host "🏗️  Iniciando build das imagens Docker..." -ForegroundColor Green

try {
    # Build Backend
    Write-Host "📦 Building backend..." -ForegroundColor Yellow
    Set-Location backend
    docker build -t "northwind-backend:$Tag" .
    docker tag "northwind-backend:$Tag" "$AcrName.azurecr.io/northwind-backend:$Tag"
    Set-Location ..

    # Build Frontend
    Write-Host "🌐 Building frontend..." -ForegroundColor Yellow
    Set-Location frontend
    docker build -t "northwind-frontend:$Tag" .
    docker tag "northwind-frontend:$Tag" "$AcrName.azurecr.io/northwind-frontend:$Tag"
    Set-Location ..

    # Build Load Generator
    Write-Host "⚡ Building load generator..." -ForegroundColor Yellow
    Set-Location loadgen
    docker build -t "northwind-loadgen:$Tag" .
    docker tag "northwind-loadgen:$Tag" "$AcrName.azurecr.io/northwind-loadgen:$Tag"
    Set-Location ..

    Write-Host "✅ Build concluído!" -ForegroundColor Green

    # Pergunta se deve fazer push
    $response = Read-Host "Fazer push para $AcrName.azurecr.io? (y/n)"
    if ($response -match '^[Yy]$') {
        Write-Host "🚀 Fazendo login no ACR..." -ForegroundColor Blue
        az acr login --name $AcrName

        Write-Host "📤 Pushing images..." -ForegroundColor Blue
        docker push "$AcrName.azurecr.io/northwind-backend:$Tag"
        docker push "$AcrName.azurecr.io/northwind-frontend:$Tag"
        docker push "$AcrName.azurecr.io/northwind-loadgen:$Tag"
        
        Write-Host "✅ Deploy concluído!" -ForegroundColor Green
    }

    Write-Host "🎯 Para aplicar no AKS:" -ForegroundColor Cyan
    Write-Host "   1. Atualizar k8s/*.yaml com seu ACR: $AcrName.azurecr.io"
    Write-Host "   2. kubectl apply -f k8s/"
}
catch {
    Write-Host "❌ Erro durante o build: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
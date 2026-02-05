#!/bin/bash

echo "🐳 Docker WebSocket Application Manager"
echo "======================================"

case "$1" in
    build)
        echo "🔨 Construindo imagem Docker..."
        docker build -t websocket-app .
        ;;
    
    run)
        echo "🚀 Executando container..."
        docker run -d --name websocket-app -p 8000:8000 websocket-app
        echo "✅ Container iniciado em http://localhost:8000"
        ;;
    
    stop)
        echo "🛑 Parando container..."
        docker stop websocket-app
        docker rm websocket-app
        ;;
    
    logs)
        echo "📋 Logs do container..."
        docker logs -f websocket-app
        ;;
    
    compose-up)
        echo "🐳 Iniciando com Docker Compose..."
        docker-compose up -d
        echo "✅ Serviços iniciados em http://localhost:8000"
        ;;
    
    compose-up-nginx)
        echo "🐳 Iniciando com Docker Compose + Nginx..."
        docker-compose --profile nginx up -d
        echo "✅ Serviços iniciados em http://localhost:80"
        ;;
    
    compose-down)
        echo "🛑 Parando Docker Compose..."
        docker-compose down
        ;;
    
    clean)
        echo "🧹 Limpando containers e imagens..."
        docker-compose down
        docker stop websocket-app 2>/dev/null || true
        docker rm websocket-app 2>/dev/null || true
        docker rmi websocket-app 2>/dev/null || true
        docker system prune -f
        ;;
    
    shell)
        echo "🐚 Entrando no container..."
        docker exec -it websocket-app bash
        ;;
    
    *)
        echo "Uso: $0 {build|run|stop|logs|compose-up|compose-up-nginx|compose-down|clean|shell}"
        echo ""
        echo "Comandos disponíveis:"
        echo "  build           - Construir imagem Docker"
        echo "  run             - Executar container simples"
        echo "  stop            - Parar e remover container"
        echo "  logs            - Ver logs do container"
        echo "  compose-up      - Iniciar com docker-compose"
        echo "  compose-up-nginx- Iniciar com docker-compose + nginx"
        echo "  compose-down    - Parar docker-compose"
        echo "  clean           - Limpar containers e imagens"
        echo "  shell           - Entrar no container"
        exit 1
        ;;
esac
#!/bin/bash

# Script de execução do servidor WebSocket Python
echo "🚀 Iniciando servidor WebSocket Python..."

# Verificar se Python está instalado
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 não encontrado. Por favor instale Python 3.8 ou superior."
    exit 1
fi

# Verificar se pip está instalado
if ! command -v pip3 &> /dev/null; then
    echo "❌ pip3 não encontrado. Por favor instale pip."
    exit 1
fi

# Verificar se o ambiente virtual existe
if [ ! -d ".venv" ]; then
    echo "📦 Criando ambiente virtual..."
    python3 -m venv .venv
fi

# Ativar ambiente virtual
source .venv/bin/activate

# Instalar dependências
echo "📦 Instalando dependências..."
pip install -r requirements.txt

# Criar diretório static se não existir
mkdir -p static

# Executar servidor
echo "🌐 Iniciando servidor em http://localhost:8000"
echo "🔗 WebSocket endpoint: ws://localhost:8000/ws"
echo "💡 Pressione Ctrl+C para parar"
echo ""

python server.py
# WebSocket Test - Python FastAPI

🎉 **Aplicação WebSocket em Python está funcionando!**

Uma aplicação simples e completa para testar conexões WebSocket usando Python FastAPI.

## ✨ O que foi criado:

1. **`server.py`** - Servidor FastAPI com WebSocket que suporta:
   - Conexões múltiplas
   - Mensagens ping/pong 
   - Broadcast para todos os clientes
   - Diferentes tipos de mensagem (echo, broadcast, ping)

2. **`static/index.html`** - Interface web com:
   - Botões Conectar/Desconectar
   - Status visual da conexão
   - Área de mensagens em tempo real
   - Input para enviar mensagens customizadas
   - Estatísticas (contador, tempo, ping)

3. **`static/app.js`** - JavaScript que gerencia:
   - Conexão/desconexão WebSocket
   - Envio e recebimento de mensagens
   - Interface do usuário responsiva
   - Medição de ping/latência

## 🚀 Como usar

### 1. Executar o servidor
```bash
./run.sh
```
ou
```bash
# Ativar ambiente virtual
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### 2. Acessar a aplicação
- **Servidor roda em**: `http://localhost:8000`
- **WebSocket endpoint**: `ws://localhost:8000/ws`
- **Status API**: `http://localhost:8000/status`

### 3. Funcionalidades disponíveis
- 🔗 **Conectar**: Estabelece conexão WebSocket
- ❌ **Desconectar**: Fecha conexão WebSocket
- 🏓 **Ping**: Teste de latência da conexão
- 📨 **Teste**: Mensagem de eco do servidor
- 📤 **Enviar**: Input para mensagens customizadas
- 📊 **Estatísticas**: Contador de mensagens, tempo de conexão e ping
- 🗑️ **Limpar**: Limpar histórico de mensagens

## 🎯 Como testar:

1. **Servidor já está rodando** em `http://localhost:8000`
2. **Abra o navegador** e acesse essa URL
3. **Clique em "Conectar"** para estabelecer WebSocket
4. **Teste as funcionalidades**:
   - 🏓 **Ping**: Teste latência (mostra tempo em ms)
   - 📨 **Teste**: Mensagem de eco
   - 📤 **Enviar**: Suas próprias mensagens
   - ❌ **Desconectar**: Fecha conexão
   - 🔗 **Conectar**: Reconecta (pode testar várias vezes!)

## 🔧 Vantagens desta solução:

- ✅ **Python simples** (sem complexidade do Node.js)
- ✅ **FastAPI moderno** (não Flask)
- ✅ **Interface visual** completa e responsiva
- ✅ **Conectar/desconectar** múltiplas vezes
- ✅ **Estatísticas em tempo real**
- ✅ **Múltiplos tipos de mensagem**
- ✅ **Fácil de entender e modificar**
- ✅ **Ambiente virtual isolado**

## 🐳 Docker

### Opção 1: Docker simples
```bash
# Construir e executar
./docker-manage.sh build
./docker-manage.sh run

# Ou manualmente
docker build -t websocket-app .
docker run -d -p 8000:8000 --name websocket-app websocket-app
```

### Opção 2: Docker Compose
```bash
# Aplicação simples
./docker-manage.sh compose-up
# ou
docker-compose up -d

# Com Nginx reverse proxy
./docker-manage.sh compose-up-nginx
# ou
docker-compose --profile nginx up -d
```

### Comandos úteis Docker
```bash
./docker-manage.sh logs     # Ver logs
./docker-manage.sh shell    # Entrar no container
./docker-manage.sh stop     # Parar containers
./docker-manage.sh clean    # Limpar tudo
```

## 📁 Estrutura do projeto
```
pocsock/
├── server.py                # Servidor FastAPI com WebSocket
├── requirements.txt         # Dependências Python
├── run.sh                  # Script de execução local
├── Dockerfile              # Configuração Docker
├── docker-compose.yml      # Orquestração de containers
├── .dockerignore           # Arquivos ignorados pelo Docker
├── docker-manage.sh        # Script de gerenciamento Docker
├── nginx.conf              # Configuração Nginx (para Docker Compose)
├── static/
│   ├── index.html         # Interface web
│   └── app.js            # Lógica JavaScript WebSocket
└── README.md             # Este arquivo
```

## 🔧 Características técnicas
- **Backend**: Python FastAPI + Uvicorn
- **WebSocket**: Nativo do FastAPI
- **Frontend**: HTML5 + JavaScript (Vanilla)
- **Funcionalidades**: Conexão/desconexão, ping/pong, broadcast, mensagens personalizadas

## 📡 Endpoints
- `GET /` - Página principal
- `WebSocket /ws` - Endpoint WebSocket
- `GET /status` - Status do servidor

## 🧪 Como testar
1. Execute `./run.sh`
2. Acesse `http://localhost:8000` no navegador
3. Clique em "Conectar"
4. Use os botões para testar diferentes funcionalidades:
   - **Ping**: Testa latência
   - **Teste**: Mensagem de eco
   - **Enviar**: Mensagem customizada
   - **Desconectar**: Fecha conexão
   - **Conectar**: Reconecta (pode testar múltiplas vezes)

## 🐛 Solução de problemas
- **Porta 8000 em uso**: Altere a porta no `server.py` linha final
- **Dependências**: Execute `pip3 install -r requirements.txt`
- **Permissões**: Execute `chmod +x run.sh`

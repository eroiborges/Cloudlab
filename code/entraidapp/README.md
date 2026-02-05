# Microsoft Entra ID OAuth2.0 Demo

Uma aplicação Flask de demonstração que implementa autenticação OAuth2.0 com Microsoft Entra ID (Azure Active Directory).

## 📋 Sobre a Aplicação

Esta aplicação demo demonstra:
- 🔐 **Autenticação OAuth2.0** com Microsoft Entra ID
- 👤 **Login/Logout** de usuários
- 📊 **Visualização de perfil** do usuário autenticado
- 🎟️ **Gerenciamento de tokens** de acesso
- ❤️ **Health checks** para monitoramento
- 🔧 **Configuração flexível** via variáveis de ambiente

## ✨ Funcionalidades

- **Login Seguro**: Redirecionamento para Microsoft Entra ID para autenticação
- **Perfil de Usuário**: Exibição das informações do usuário logado
- **Tokens de Acesso**: Visualização e monitoramento dos tokens OAuth
- **Sessão Gerenciada**: Controle de sessão com timeout configurável
- **Interface Responsiva**: Templates HTML com Bootstrap

## 🛠️ Pré-requisitos

- Python 3.9+
- Uma aplicação registrada no Microsoft Entra ID
- Pipenv ou venv para ambiente virtual (recomendado)

## ⚙️ Configuração

### 1. Registrar Aplicação no Azure

1. Acesse o [Azure Portal](https://portal.azure.com)
2. Vá para **Azure Active Directory** > **App registrations**
3. Clique em **New registration**
4. Configure:
   - **Nome**: EntraID Demo App
   - **Redirect URI**: `http://localhost:5000/auth/callback` (para desenvolvimento local)

### 2. Variáveis de Ambiente

Crie um arquivo `.env` ou configure as seguintes variáveis:

```bash
# Obrigatórias
AZURE_TENANT_ID=seu-tenant-id
AZURE_CLIENT_ID=seu-client-id
AZURE_CLIENT_SECRET=seu-client-secret
AZURE_AUTHORITY=https://login.microsoftonline.com/seu-tenant-id
FLASK_SECRET_KEY=sua-chave-secreta-muito-longa-e-segura
FLASK_HOST=0.0.0.0
FLASK_PORT=5000

# Opcionais
APP_ENVIRONMENT=dev
SESSION_TIMEOUT_MINUTES=5
CUSTOM_FQDN=localhost
```

> 📝 **Dica**: Use `python -c "import secrets; print(secrets.token_hex(32))"` para gerar uma chave secreta segura.

## 🚀 Executando Localmente

### Opção 1: Ambiente Virtual Tradicional

```bash
# Clone e navegue para o diretório
cd entraidapp

# Crie um ambiente virtual
python -m venv venv

# Ative o ambiente virtual
# Linux/macOS:
source venv/bin/activate
# Windows:
# venv\Scripts\activate

# Instale as dependências
pip install -r requirements.txt

# Configure as variáveis de ambiente
export AZURE_TENANT_ID="seu-tenant-id"
export AZURE_CLIENT_ID="seu-client-id"
# ... (demais variáveis)

# Execute a aplicação
python app.py
```

### Opção 2: Com arquivo .env

```bash
# Instale python-dotenv
pip install python-dotenv

# Crie o arquivo .env com suas configurações
# Execute a aplicação (ela carregará o .env automaticamente)
python app.py
```

A aplicação estará disponível em: http://localhost:5000

## 🌐 Endpoints Disponíveis

- **`/`** - Página inicial
- **`/login`** - Iniciar processo de autenticação
- **`/auth/callback`** - Callback OAuth (configurado no Azure)
- **`/profile`** - Perfil do usuário autenticado
- **`/tokens`** - Visualizar tokens de acesso
- **`/logout`** - Encerrar sessão
- **`/health`** - Health check da aplicação

## 📁 Estrutura do Projeto

```
entraidapp/
├── app.py                 # Aplicação Flask principal
├── config.py             # Gerenciamento de configuração
├── requirements.txt       # Dependências Python
├── README.md             # Este arquivo
├── templates/            # Templates HTML
│   ├── base.html         # Layout base
│   ├── index.html        # Página inicial
│   ├── profile.html      # Página de perfil
│   ├── tokens.html       # Página de tokens
│   └── error.html        # Página de erro
├── Dockerfile            # Para containerização
├── build-and-deploy.sh   # Script de build/deploy
├── env-variables.txt     # Exemplo de variáveis
└── k8s/                  # Manifests Kubernetes
    ├── configmap.yaml    # ConfigMap e Secrets
    └── deployment.yaml   # Deployment e Service
```

## 🐳 Deploy com Docker e Kubernetes

Para instruções detalhadas sobre containerização e deploy em Kubernetes, consulte:

**📖 [README-Docker-K8s.md](README-Docker-K8s.md)**

Este guia inclui:
- Build de imagem Docker otimizada
- Deploy em Kubernetes
- Configuração de Ingress
- Health checks e monitoramento

## 🔧 Desenvolvimento

### Dependências Principais

- **Flask 3.0.0**: Framework web
- **MSAL 1.34.0**: Microsoft Authentication Library
- **Requests 2.31.0**: Cliente HTTP

### Logs e Debug

A aplicação inclui logs detalhados para desenvolvimento:

```bash
# Execute com debug habilitado
FLASK_ENV=development python app.py
```

## 🔒 Segurança

- ✅ Tokens são armazenados apenas em sessão (não persistidos)
- ✅ Chave secreta configurável via ambiente
- ✅ Timeout de sessão configurável
- ✅ Validação de configuração na inicialização
- ✅ HTTPS recomendado para produção

## 🆘 Solução de Problemas

### Erro: "Missing required environment variables"
- Verifique se todas as variáveis obrigatórias estão definidas
- Use `python -c "from config import app_config; print(app_config.get_status())"` para validar

### Erro de redirect_uri
- Certifique-se que o URL de callback está registrado no Azure AD
- Para desenvolvimento local: `http://localhost:5000/auth/callback`

### Problemas de token
- Verifique se o client_secret está correto
- Confirme se a aplicação tem as permissões necessárias no Azure AD

---

## 📞 Suporte

Para dúvidas sobre containerização e deploy, consulte o [README-Docker-K8s.md](README-Docker-K8s.md).

**Happy coding!** 🚀
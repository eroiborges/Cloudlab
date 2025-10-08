# GetHeaders - Backend Troubleshooting Tool

**Versão**: 2.0  
**Python**: 3.12  
**Propósito**: Ferramenta de troubleshooting para load balancers e proxies reversos

## 📋 Visão Geral

Este serviço foi desenvolvido especificamente para **troubleshooting de load balancers**, permitindo verificar como os requests chegam aos backends. É uma ferramenta essencial para debuggar configurações de:

- Load Balancers (NGINX, HAProxy, AWS ALB/NLB, Azure Load Balancer)
- Proxies Reversos
- Service Mesh (Istio, Linkerd)
- Kubernetes Ingress Controllers
- CDNs e edge proxies

## 🚀 Quick Start

### Build e Execução

```bash
# Build da imagem
docker build -t getheader-backend:v2 .

# Executar container
docker run -p 8080:8080 getheader-backend:v2

# Testar se está funcionando
curl http://localhost:8080/health
```

### Execução Local (Desenvolvimento)

```bash
# Instalar dependências
pip install -r requirements.txt

# Executar localmente
python getheader.py

# Acesso: http://localhost:8080
```

## 📡 Endpoints Disponíveis

### 1. `/health` - Health Check
**Métodos**: GET, HEAD  
**Propósito**: Health check para load balancers

```bash
# Health check completo
curl http://localhost:8080/health

# Health check leve (HEAD) - usado por LBs
curl -I http://localhost:8080/health
```

**Resposta GET**:
```json
{
  "status": "healthy",
  "service": "getheader-backend",
  "version": "v1",
  "timestamp": "2025-10-08T10:30:45.123456+00:00",
  "hostname": "container-hostname",
  "uptime_check": "ok"
}
```

### 2. `/headers` - HTTP Headers
**Método**: GET  
**Propósito**: Verificar headers que chegam ao backend

```bash
curl http://localhost:8080/headers
```

### 3. `/getip` - Informações de IP
**Método**: GET  
**Propósito**: Verificar IPs (local, remote, X-Real-IP, X-Forwarded-For)

```bash
curl http://localhost:8080/getip
```

### 4. `/test-params` - Query String Parameters ⭐ NOVO
**Método**: GET  
**Propósito**: Testar rewriting de URLs e parâmetros

```bash
# Teste básico
curl "http://localhost:8080/test-params?user=john&env=prod&trace=123"

# Teste com caracteres especiais
curl "http://localhost:8080/test-params?search=hello%20world&filter=active"
```

**Resposta**:
```json
{
  "message": "Query string parameters received successfully",
  "query_params": {
    "user": "john",
    "env": "prod",
    "trace": "123"
  },
  "param_count": 3,
  "url_info": {
    "full_url": "http://localhost:8080/test-params?user=john&env=prod&trace=123",
    "base_url": "http://localhost:8080/test-params",
    "url_root": "http://localhost:8080/",
    "path": "/test-params",
    "raw_query_string": "user=john&env=prod&trace=123"
  },
  "headers": {...},
  "date": "2025-10-08T...",
  "api_version": "v1"
}
```

### 5. `/body` - Request Body
**Método**: POST  
**Propósito**: Verificar conteúdo do body

```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"test": "data"}' \
  http://localhost:8080/body
```

### 6. `/all` - Informações Completas
**Método**: POST  
**Propósito**: Headers + IPs + Body em uma única resposta

```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"environment": "test"}' \
  http://localhost:8080/all
```

## 🔍 Cenários de Troubleshooting

### 1. **Teste de Health Check de Load Balancer**

```bash
# Simular health check do NGINX
curl -I http://backend:8080/health

# Simular health check do HAProxy
curl -X GET http://backend:8080/health

# Kubernetes liveness/readiness probe
kubectl exec -it pod -- curl localhost:8080/health
```

### 2. **Verificar Headers do Load Balancer**

```bash
# Verificar se LB está passando headers corretos
curl -H "X-Custom-Header: test123" http://lb.example.com/headers

# Headers típicos para verificar:
# - X-Forwarded-For
# - X-Real-IP  
# - X-Forwarded-Proto
# - X-Forwarded-Host
# - User-Agent
```

### 3. **Troubleshooting de IP/Proxy**

```bash
# Verificar chain de IPs através de proxies
curl http://lb.example.com/getip

# Verificar se X-Real-IP está sendo setado
curl -H "X-Real-IP: 192.168.1.100" http://backend:8080/getip
```

### 4. **Teste de URL Rewriting**

```bash
# Testar se LB está reescrevendo URLs
curl "http://lb.example.com/api/v1/test-params?original=true"

# Verificar se parâmetros são preservados
curl "http://lb.example.com/test-params?session=abc&user=admin"

# Teste com caracteres especiais
curl "http://lb.example.com/test-params?query=hello%20world&filter=%3E100"
```

### 5. **Verificar Body Forwarding**

```bash
# Testar se body está sendo repassado corretamente
curl -X POST -H "Content-Type: application/json" \
  -d '{"timestamp": "2025-10-08", "data": {"key": "value"}}' \
  http://lb.example.com/body
```

### 6. **Teste Completo de Request**

```bash
# Verificar headers + body + IPs simultaneamente
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Trace-ID: trace-123" \
  -H "X-User-ID: user-456" \
  -d '{"test_scenario": "complete_test", "environment": "production"}' \
  http://lb.example.com/all
```

## ⚙️ Configurações de Load Balancer

### NGINX

```nginx
upstream backend {
    server backend1:8080;
    server backend2:8080;
}

server {
    listen 80;
    
    # Health check endpoint
    location /health {
        proxy_pass http://backend/health;
        access_log off;  # Evita spam nos logs
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # Application endpoints
    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### HAProxy

```
backend web_servers
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    
    server web1 10.0.0.1:8080 check inter 30s
    server web2 10.0.0.2:8080 check inter 30s

frontend web_frontend
    bind *:80
    option httplog
    option forwardfor
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    default_backend web_servers
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: getheader-backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: getheader-backend
  template:
    metadata:
      labels:
        app: getheader-backend
    spec:
      containers:
      - name: getheader
        image: getheader-backend:v2
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: getheader-service
spec:
  selector:
    app: getheader-backend
  ports:
  - port: 80
    targetPort: 8080
  type: LoadBalancer
```

## 🐳 Docker

### Multi-stage Build (Opcional)

```dockerfile
# Build stage
FROM python:3.12-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

# Production stage
FROM python:3.12-slim
COPY --from=builder /root/.local /root/.local
WORKDIR /app
COPY getheader.py .
ENV PATH=/root/.local/bin:$PATH
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "getheader:app"]
```

## 🔧 Troubleshooting Common Issues

### 1. Container não responde ao health check
```bash
# Verificar se container está executando
docker ps

# Verificar logs
docker logs <container_id>

# Testar diretamente no container
docker exec -it <container_id> curl localhost:8080/health
```

### 2. Headers não chegam corretamente
```bash
# Verificar configuração do proxy
curl -v http://lb.example.com/headers

# Comparar com acesso direto
curl -v http://backend:8080/headers
```

### 3. IPs incorretos
```bash
# Verificar chain de proxies
curl http://backend:8080/getip

# Headers de IP para verificar:
# - remote_ip (IP direto)
# - Real_ip (X-Real-IP header)  
# - xff (X-Forwarded-For chain)
```

## 📊 Monitoramento

### Métricas Importantes
- Response time dos endpoints
- Status codes retornados
- Número de health checks
- Headers únicos recebidos

### Logs para Analisar
```bash
# Logs do container
docker logs getheader-backend

# Logs do Gunicorn (produção)
# Configurados para stdout/stderr
```

## 🔄 Atualizações Futuras

### Roadmap Planejado
- [ ] Logging estruturado com correlation IDs
- [ ] Tratamento robusto de erros
- [ ] Métricas Prometheus
- [ ] Support para HTTP/2
- [ ] Endpoint para WebSocket testing

## 📝 Contribuição

Para adicionar novos cenários de teste ou melhorias:

1. Testar localmente
2. Atualizar este README
3. Verificar compatibilidade com Python 3.12
4. Adicionar casos de teste específicos

## 🏷️ Versioning

- **v1.0**: Versão inicial com Python 3.9
- **v2.0**: Python 3.12, health check, query params, Gunicorn, boas práticas Docker

---

**Desenvolvido para troubleshooting de infraestrutura de rede e load balancing** 🔧
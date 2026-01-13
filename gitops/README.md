# Kustomization para Produção

Esta estrutura utiliza Kustomize para gerenciar os deployments do ambiente de produção.

## Estrutura de Diretórios

```
gitops/
├── base/
│   ├── kustomization.yaml          # Configurações base
│   ├── deploy-header.yaml          # Deployment base (copiado)
│   └── svc-getheader.yaml         # Service base (copiado)
├── overlays/
│   └── production/
│       ├── kustomization.yaml      # Configuração de produção
│       ├── namespace.yaml          # Definição do namespace
│       ├── deployment-patch.yaml   # Patches específicos para o deployment
│       └── service-patch.yaml      # Patches específicos para o service
├── deploy-header.yaml              # Arquivo original do deployment
└── svc-getheader.yaml             # Arquivo original do service
```

## Como usar

### Para aplicar os recursos de produção:

```bash
# Visualizar os recursos que serão criados
kubectl kustomize overlays/production

# Aplicar no cluster
kubectl apply -k overlays/production
```

### Para verificar o status:

```bash
# Verificar pods no namespace de produção
kubectl get pods -n getheader-production

# Verificar services
kubectl get svc -n getheader-production
```

## Configurações de Produção

- **Namespace**: `getheader-production`
- **Replicas**: 3 instâncias
- **Prefixo**: `prod-` para todos os recursos
- **Resource Limits**: Configurados para produção
- **Health Checks**: Readiness e liveness probes configurados
- **Service**: LoadBalancer com session affinity

## Personalização

Para alterar configurações específicas de produção, edite os arquivos de patch:

- `deployment-patch.yaml`: Para ajustar configurações do deployment
- `service-patch.yaml`: Para ajustar configurações do service

## CI/CD

Para usar em pipelines, você pode sobrescrever a tag da imagem:

```bash
kubectl kustomize overlays/production | kubectl set image deployment/prod-getheader getheader=rsykba1j6kcp6.azurecr.io/getheader-backend:v3
```
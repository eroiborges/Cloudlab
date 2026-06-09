# Comparativo OpenShift, ARO e AKS

## Tabela consolidada

| Categoria | Componente | Openshift OnPrem | ARO | AKS | Observacoes | Documentacao |
|---|---|---|---|---|---|---|
| Networking | CNI | OpenshiftSDN / OVN-Kubernetes | OpenshiftSDN / OVN-Kubernetes | Kubenet / Legacy Azure CNI (Node subnet) / Azure CNI Overlay | Priorizar Azure CNI Overlay para escala e simplicidade operacional. | [Microsoft Learning](https://learn.microsoft.com/en-us/azure/aks/concepts-network) |
| Networking | Load Balancer | F5 | Standard LB | Standard LB | Separar claramente L4 (Service LB) e L7 (Ingress). | [Standard LB](https://learn.microsoft.com/en-us/azure/aks/internal-lb?tabs=set-service-annotations) |
| Networking | Integração com NLB | Não | Sim | Sim, para criação das regras de LB | Usar Service type LoadBalancer com anotações quando necessário. | [Standard LB](https://learn.microsoft.com/en-us/azure/aks/internal-lb?tabs=set-service-annotations) |
| Networking | Integração com ALB | - | - | Application Gateway for Containers<BR>Application Gateway Ingress Controller | AGfC para novo padrão L7 gerenciado; AGIC para cenários legados. | [Application Gateway for Containers](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/overview?toc=/azure/aks/toc.json&bc=/azure/aks/breadcrumb/toc.json)<BR>[Application Gateway Ingress Controller](https://learn.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview) |
| Networking | CIDR SVC/Pod | Default | De acordo com a RFC 6598 (100.64.0.0/10) | Default K8S e alinhado ao tipo de CNI | Definir faixas sem sobreposição com rede corporativa e VPN. | [Plan networking](https://learn.microsoft.com/en-us/azure/aks/plan-networking) |
| Networking | Ingress Controller | HAProxy | HAProxy | Any Self Managed<BR>Microsoft Managed | Escolher por requisitos de segurança, TLS e governança corporativa. | [Microsoft Managed](https://learn.microsoft.com/en-us/azure/aks/concepts-network-ingress#compare-ingress-options) |
| Observabilidade | Escopo de monitoracao | Cluster + Aplicacoes | Cluster + Aplicacoes | Cluster + Aplicacoes (Plataforma e App) | Separar no desenho o que e sinal de plataforma e o que e sinal de workload. | [Monitor AKS](https://learn.microsoft.com/en-us/azure/aks/monitor-aks) |
| Observabilidade | Logging Backend | Elasticsearch | Elastic Cloud | Log Analytics (padrao) ou Elastic Cloud | Elastic pode ser destino de logs de app e/ou plataforma via roteamento. | [Data storage](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#data-storage) |
| Observabilidade | Log Forwarder / Coletor | fluentd | fluentd | Azure Monitor Agent (Container Insights) ou Fluent Bit/Fluentd | No AKS, o caminho nativo e AMA; Fluentd vira opcao de integracao. | [Container insights](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview) |
| Observabilidade | Logs de control plane | Operacao da plataforma OCP | Operacao da plataforma ARO | AKS Resource Logs (AKSControlPlane, AKSAudit, AKSAuditAdmin) | Exige Diagnostic Settings; preferir modo resource-specific por custo e consulta. | [AKS resource logs](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#azure-monitor-resource-logs) |
| Observabilidade | Logs de workload | Logs de pods/apps | Logs de pods/apps | Container Insights (ContainerLogV2, KubeEvents, KubePodInventory) | Usar DCR para reduzir custo de ingestao e ajustar escopo de coleta. | [AKS data plane logs](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#aks-data-plane-container-insights-logs) |
| Observabilidade | Monitoring (metricas) | Prometheus + AlertManager | Prometheus + AlertManager | Platform Metrics + Managed Prometheus + Managed Grafana | Plataforma e objetos K8s podem ser monitorados juntos no Grafana. | [AKS metrics](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#azure-monitor-platform-metrics) |
| Observabilidade | Tracing Collector | OpenTelemetry OSS | OpenTelemetry OSS | OpenTelemetry Collector (export App Insights, Dynatrace ou Elastic) | OTel unifica telemetria de aplicacao e facilita multi-backend. | [Application Insights and OpenTelemetry](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#aks-monitoring-data-metrics-logs-integrations) |
| Observabilidade | APM | Dynatrace | Dynatrace | Dynatrace ou Application Insights | Tratar APM como camada de app, nao substitui observabilidade de cluster. | [Monitor AKS](https://learn.microsoft.com/en-us/azure/aks/monitor-aks) |
| Observabilidade | Alertas | AlertManager | AlertManager | Metric Alerts, Log Alerts, Activity Log Alerts, Prometheus Alerts | Criar baseline com alertas recomendados para cluster, node e pod. | [AKS alerts](https://learn.microsoft.com/en-us/azure/aks/monitor-aks#alerts) |
| Segurança | Autenticação | OpenID + LDAP | OpenID + SSO(Entra) | Microsoft Entra ID + Kubernetes RBAC | Definir grupos Entra para perfis de acesso (admin, ops, dev, read-only). | [AKS + Entra ID](https://learn.microsoft.com/en-us/azure/aks/managed-azure-ad) |
| Segurança | Compliance (NIST etc) | Compliance Operator | Compliance Operator | Azure Policy for AKS + Defender for Cloud (regulatory compliance) | Usar iniciativas por baseline (CIS/NIST) e acompanhar drift por recomendacoes. | [Azure Policy for AKS](https://learn.microsoft.com/en-us/azure/aks/use-azure-policy) |
| Segurança | Políticas de Postura | RHACS | RHACS | Defender for Containers + Azure Policy + RHACS (mantido) + (opcional) Qualys | RHACS pode ser mantido no AKS para continuidade operacional; definir ferramenta fonte da verdade para alertas e politicas. | [Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction) |
| Segurança | Acesso | RBAC K8S | RBAC K8S + IAM (Managed Identity) | Kubernetes RBAC + Azure RBAC for Kubernetes Authorization | Evitar contas compartilhadas e aplicar least privilege por namespace/cluster role. | [Azure RBAC for Kubernetes](https://learn.microsoft.com/en-us/azure/aks/manage-azure-rbac) |
| Segurança | Integração Cloud |  | Managed Identity / SPN | Managed Identity (control plane) + Workload Identity (pods) | Priorizar Workload Identity no lugar de secrets/SPN em workloads. | [Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview) |
| Segurança | Secret Manager | - | KeyVault - via K8s Secrets Store CSI | Azure Key Vault + Secrets Store CSI Driver | Evitar segredos em texto no cluster; usar rotacao no Key Vault e acesso por identidade. | [CSI + Key Vault on AKS](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) |
| Segurança | Certificate Management | certmanager (para certs da plataforma) Ingress - procedimento de renovação manual | certmanager (para certs da plataforma) Ingress - procedimento de renovação manual | cert-manager + Key Vault (issuer/integração) + automação de renovação | Tratar certificados de ingress e mTLS com ciclo de vida automatizado. | [TLS and cert management in AKS](https://learn.microsoft.com/en-us/azure/aks/ingress-tls) |
| Segurança | Backup |  | OADP | Azure Backup for AKS (extensão Velero) | Definir RPO/RTO por namespace e validar restore em ambiente de teste. | [Azure Backup for AKS](https://learn.microsoft.com/en-us/azure/backup/azure-kubernetes-service-backup-overview) |
| Storage | CSI Drivers | CEPH | - | Azure Disk CSI + Azure File CSI (+ Snapshot CSI) | Padronizar storage class por workload: bloco para banco e file share para compartilhamento. | [CSI drivers on AKS](https://learn.microsoft.com/en-us/azure/aks/csi-storage-drivers) |
| Storage | Storage Backends | CEPH NFS GPFS Vsphere | Azure Disk Azure Files (SMB/NFS) | Azure Disk, Azure Files (SMB/NFS), Azure NetApp Files (quando necessario) | Definir tiers por IOPS/latencia e politica de backup por classe de dado. | [Storage options for AKS](https://learn.microsoft.com/en-us/azure/aks/concepts-storage) |
| Arquitetura | Autoscaler Nodes | Cluster Autoscaling | Cluster Autoscaling | Autoscaler / Node Auto Provisioning | Autoscaler para nodepools imutáveis e NAP para nodepools mistos com foco em densidade computacional e otimização de custos. | [Node auto-provisioning in Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning)<BR><BR>[Cluster autoscaling in Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/cluster-autoscaler-overview) |
| Arquitetura | Autoscaler Workloads | HPA / VPA | HPA / VPA | HPA / VPA / Keda | HPA e VPA seguem o mesmo conceito. Addon oficial Keda para escala baseada em uso real e eventos através de custom métrics | [Kubernetes Event-driven Autoscaling](https://learn.microsoft.com/en-us/azure/aks/keda-about)<BR><BR>[Autoscale pods](https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-scale?tabs=azure-cli#autoscale-pods)<BR><BR>[Vertical Pod Autoscaler in Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/use-vertical-pod-autoscaler) |
| Arquitetura | Hosted Control Plane  | Não | Não | Free / Standard / Premium | Control plane 100% gerenciado pela Microsoft. SKUs definem SLA, tempo de suporte e sizing. | [AKS Control Plane](https://learn.microsoft.com/en-us/azure/aks/core-aks-concepts#control-plane)<BR><BR>[AKS pricing tiers](https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers) |
| Arquitetura | Arquitetura Ativo-Ativo  | Balanceamento via F5 entre todos os infra nodes (Router) | Balanceamento via Application Gateway entre os NLB de cada cluster ARO | Exposição via Traffic Manager, Frontdoor ou multi-cluster networking com Fleet-Manager | Configuração manual de entry-point ou gerenciado com fleet-manager. | [AKS active-active high availability solution overview](https://learn.microsoft.com/en-us/azure/aks/active-active-solution)<BR><BR>[Fleet Manager multi-cluster networking overview](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/concepts-multi-cluster-networking-overview) |
| Service Mesh | Tecnologia | Openshift Service Mesh 2.x | Openshift Service Mesh 2.x | Istio OSS (add-on) ou Open Service Mesh (legado) | Adotar mesh por necessidade real de mTLS, traffic shaping e observabilidade L7. | [Istio add-on for AKS](https://learn.microsoft.com/en-us/azure/aks/istio-about) |
| Governança | Finops |  | Apptio | Apptio + Azure Cost Management + tagging strategy | Medir custo por cluster, node pool e namespace com labels/tags padronizadas. | [AKS cost optimization](https://learn.microsoft.com/en-us/azure/aks/best-practices-cost) |

## Leitura inicial para demo

- Itens com direcionamento AKS explícito: 23
- Itens com gap funcional no AKS: 0 (existem apenas decisões de arquitetura por cenário)

## Trilhas sugeridas para apresentação

### Trilha 1 - Networking e Entrada
- CNI no AKS: Azure CNI Overlay como padrão recomendado para escala e simplicidade.
- Ingress: NGINX Ingress Controller no cluster e opção de integração com Application Gateway (AGIC) para cenários enterprise.
- Load Balancer: Standard Load Balancer e desenho L4/L7 com responsabilidades claras.

### Trilha 2 - Observabilidade
- Logging: Azure Monitor Container Insights + Log Analytics como caminho principal.
- Métricas: Azure Managed Prometheus e painéis no Managed Grafana.
- Tracing/APM: OpenTelemetry collector com export para Dynatrace e/ou Application Insights.

### Trilha 3 - Segurança e Identidade
- Acesso ao Azure: Managed Identity (Workload Identity no AKS) substituindo SPN onde possível.
- Segredos: Secrets Store CSI Driver com Azure Key Vault.
- Postura e compliance: Defender for Containers + políticas de Azure Policy para AKS.

### Trilha 4 - Plataforma e Governança
- RBAC Kubernetes + Azure RBAC (quando aplicável) e segregação por namespaces.
- FinOps: tags, quotas e análise de custo por cluster/node pool/workload.
- Padrão operacional: baseline de cluster, addons e guardrails.

### Trilha 5 - Storage e Backup
- Storage classes com Azure Disk e Azure Files (SMB/NFS) por tipo de workload.
- Estratégia de backup com Velero + snapshots de volume e retenção por criticidade.

### Trilha 6 - Arquitetura
- Autoscaling de Nodes e Workloads
- SKUs do Control Plane
- Posibilidades de arquitetura Ativo-Ativo

### Trilha 7 - Service Mesh
- Istio OSS no AKS para cenários que exigem mTLS, roteamento avançado e observabilidade de tráfego.
- Definir critério de adoção: usar mesh apenas para workloads que realmente precisam.

## Itens para priorizar na demo (fase 1)

1. Networking: CNI Overlay + Ingress + balanceamento L4/L7.
2. Segurança: Workload Identity + Key Vault CSI + políticas.
3. Observabilidade: logs/métricas/traces em fluxo único com OpenTelemetry.
4. Storage e continuidade: classes de armazenamento + backup e restore.

## Roteiro sugerido (30-40 min)

### 1. Contexto e objetivo (3-5 min)
- Contexto atual do cliente: OpenShift OnPrem e ARO em operação.
- Objetivo: mostrar equivalência funcional no AKS e decisões arquiteturais.
- Mensagem executiva: AKS cobre os mesmos domínios, com choices de implementação.

### 2. Visão comparativa consolidada (5-7 min)
- Percorrer a tabela por domínio: Networking, Observabilidade, Segurança, Storage, Service Mesh e Governança.
- Destacar que nao existe gap funcional critico; existem opcoes de arquitetura por cenário.
- Mensagem executiva: transição é principalmente desenho operacional e governança.

### 3. Networking no AKS (5-6 min)
- CNI: recomendação de Azure CNI Overlay.
- Entrada L4/L7: Standard Load Balancer + Ingress (self-managed ou managed).
- ALB no Azure: AGfC/AGIC conforme maturidade e padrao do ambiente.
- Mensagem executiva: baseline simples e escalável para adotar rapidamente.

### 4. Observabilidade em dois escopos (6-7 min)
- Plataforma: control plane logs, activity log, platform metrics e alertas.
- Aplicação: logs de workload, OTel tracing, APM.
- Caminho recomendado: Container Insights + Managed Prometheus + Managed Grafana + backend APM corporativo.
- Mensagem executiva: separar sinais de plataforma e app evita ambiguidade e acelera troubleshooting.

### 5. Segurança e identidade (6-7 min)
- Autenticação/autorização: Entra ID + Kubernetes RBAC + Azure RBAC.
- Segredos e identidade de workload: Key Vault CSI + Workload Identity.
- Postura: Defender/Azure Policy, mantendo RHACS quando fizer sentido no cliente.
- Mensagem executiva: segurança por camadas com continuidade operacional.

### 6. Storage, mesh e governança (4-5 min)
- Storage: Azure Disk/Azure Files/ANF por perfil de carga.
- Service Mesh: Istio quando houver necessidade clara de mTLS e tráfego L7 avançado.
- FinOps: custo por cluster/node pool/namespace com tagging e Azure Cost Management.
- Mensagem executiva: padronização desde o dia 1 reduz risco de custo e operação.

### 7. Fechamento e próximos passos (2-3 min)
- Propor piloto em workload representativo.
- Definir baseline de plataforma e checklist de produção.
- Consolidar plano de migração por ondas (low-risk to high-critical).

## Demos recomendadas (15 min total)

### Demo 1 - Observabilidade ponta a ponta (6 min)
Objetivo:
- Mostrar separação entre plataforma e aplicação no AKS.

Passos:
1. Abrir AKS Insights no portal e mostrar health do cluster/nodes.
2. Mostrar logs de control plane em Log Analytics (AKSControlPlane/AKSAudit).
3. Abrir dashboard no Managed Grafana com métricas de cluster/pod.
4. Mostrar logs de aplicação (ContainerLogV2) e um trace (Dynatrace/App Insights).

Mensagem final:
- Um único fluxo operacional para detectar, correlacionar e resolver incidentes.

### Demo 2 - Segurança de workload e segredos (5 min)
Objetivo:
- Mostrar segurança prática sem segredo hardcoded e com identidade nativa.

Passos:
1. Exibir workload usando Workload Identity.
2. Mostrar leitura de segredo via Key Vault CSI (sem credencial em texto).
3. Exibir política de postura (Defender/Azure Policy e opcional RHACS) e resultado de compliance.

Mensagem final:
- Segurança by design com governança e continuidade para ambientes que ja usam RHACS.

### Demo 3 - Continuidade e operação (4 min)
Objetivo:
- Demonstrar previsibilidade operacional para dados e custo.

Passos:
1. Mostrar storage class e PVC de exemplo (Azure Disk/Azure Files).
2. Exibir política/execução de backup (Azure Backup for AKS).
3. Mostrar visão de custo por cluster ou node pool (Cost Management/Apptio).

Mensagem final:
- Operação sustentável: performance, proteção de dados e visibilidade de custo.

## Pré-requisitos para demo

1. Cluster AKS com Monitoring habilitado (Container Insights + Managed Prometheus + Grafana).
2. Workspace de Log Analytics e alertas básicos configurados.
3. Key Vault e Workload Identity já preparados para um app de exemplo.
4. Pelo menos um namespace com aplicação de teste gerando logs/metrics/traces.
5. (Opcional) RHACS conectado ao cluster para cenário de continuidade do cliente.

## Plano B (se ambiente ao vivo falhar)

1. Screenshots dos dashboards e consultas KQL salvas previamente.
2. Vídeo curto (2-3 min) da execução da demo mais crítica.
3. Queries KQL e painéis favoritos prontos para replay rápido.

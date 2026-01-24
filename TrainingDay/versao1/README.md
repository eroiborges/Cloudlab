# Training Day

## Objetivo
Este workshop prático foi projetado para equipá-lo com as habilidades necessárias para projetar a infraestrutura para apoiar projetos de Inteligência Artificial, como projetar <br> e implementar uma infraestrutura nativa da nuvem para hospedar soluções de Inteligência Artificial implementando alta disponibilidade, segurança e governança.<br>

## Audiência
Solution, Infrastructure e Security Architects e Cloud Administrators.

## Tecnologias
Azure Network, Azure Security, Azure Containers services, Azure APIM, Azure DBs

## Conteúdo  

1. Definir a arquitetura de infraestrutura de projetos de Inteligência Artificial usando o [Cloud Adoption Framework para Inteligencia Artifical](https://aka.ms/cafai)
2. Data Migration (SQL DB/PGSQL) for non-DBAs.
3. Azure Network e Security. (DNS strategy, Private Endpoint, Network Security e Monitoring)
4. Scaling e Security for AI, Azure APIM, Sentinel, Defender For Cloud, e Security Copilot
5. Governança para AI - Azure Monitor e Azure Policy
6. Application Platform - Como preparar um ambiente de Serviços de Kubernetes do Azure e um Aplicativo para Contêiner para hospedar soluções de Inteligência Artificial.

## Requisitos

1. Computador individual para a execução de laboratórios com acesso à internet.
2. Uma Subscription Azure.
3. Docker client instalado no shell bash ou CloudShell para login no Azure Registry

## Setup do laborario

### instruções iniciais

O Laboratorio foi desenvolvimento para executar através do AzureCLI com shell bash. Você pode utilizar uma instalação local em seu computador com o [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) ou através do [Azure Cloud Shell](<https://learn.microsoft.com/pt-br/azure/cloud-shell/overview>)

Versões do AZCli utilizadas:

| Ambiente | versão |
| -------- | ------ |
| **Desktop** | Azure-cli:2.62.0 |
| **CloudShell** | azure-cli: 2.65.0|
| | |

### Credenciais

As credenciais utilizadas para acesso RDP/SSH a uma maquina virtual ou acesso ao serviço de Banco de Dados.

| Tipo | Login | Password | Comentário |
| -------- | -------- | ------ | ------ |
| Windows |  **Localadmin** | b2xhbXVuZG8xMjM=| Login RDP da VM |
| Linux   | **pgadmin** | b2xhbXVuZG8xMjM=| Login SSH da VM |
| PGSQL User | **demouser** | demopass123| Login na instancia local do PGSQL da VM Linux |
| AzSQLDB |  **dbadmin** | b2xhbXVuZG8xMjM=| login da instancia PaaS Azure SQL |
| AzPGSQL |  **dbadmin** | b2xhbXVuZG8xMjM=| login da instancia PaaS Postgre SQL |
|  | |

> Nota: Cuidado com espaços inseridos pelo HTML, copie a senha em um notepad.

## Documentação de referência

Todo o contexto do treinamento é baseado na documentação do Microsoft Azure, na comunidade técnica ou na página pública do GitHub que pode ser usada para aprofundar cada conteúdo fora das atividades de treinamento.

## Links uteis

* [Cloud Adoption Framework](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/)
* [Terraform CAF EnterpriseScale](https://github.com/Azure/terraform-azurerm-caf-enterprise-scale)
* [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)

## Modulos

0. Introdução
    + [Setup Inicial](00-Setup-lab.md)
1. NETWORK
    + [Azure Network and Security](Network-01.md)
    + [DNS](Network-02.md)
    + [Application Gateway / Web Application firewall](Network-03.md)
    + [Monitoring](Network-04.md)
2. IDENTITY
    + [Metadata Service](metadataservices.md)
    + [Autenticação Entra ID - SQL](authentra.md)
3. MIGRATION
    + [PostgreSQL](migracaopgsql.md)
    + [MS SQL](MigracaoSQLDB.md)
4. SECURITY
    + [Defender For Cloud](DefenderForCloud.md)
    + [Azure Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/quickstart-onboard)
5. APPLICATION
    + [Azure APIM](AzureAPIM.md)
    + [Azure Kubernetes Services](kubernetes.md)
    + [Azure Container Apps](containerapps.md)
6. MONITORAÇÃO
    + [Azure Monitor](monitor.md)
7. GOVERNANÇA
    + [Azure Policy](azurepolicy.md)
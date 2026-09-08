# Ativação do custom domain

Este diretório é uma raiz Terraform independente e possui seu próprio state. Executar o Terraform a partir do diretório pai não executa os recursos desta pasta, pois o Terraform não carrega subdiretórios automaticamente.

## Pré-requisitos

1. Aplique a raiz Terraform do diretório pai para criar a Web App, importar o PFX e gerar `pilot.auto.tfvars.json`.
2. Crie os dois registros descritos em `handoff.route53.records` na zona pública do Route 53.
3. Confirme que os registros TXT e CNAME resolvem por meio do DNS público.

## Ativar o domínio

Execute o Terraform neste diretório e libere explicitamente o gate de validação do DNS:

```powershell
terraform init
terraform validate
terraform plan -var="dns_validation_confirmed=true" -out custom-domain.tfplan
terraform apply custom-domain.tfplan
```

O binding usa TLS com SNI porque TLS baseado em IP não é suportado com Private Endpoint do App Service.

Mantenha o registro TXT de verificação no Route 53 enquanto o custom domain estiver em uso para reduzir o risco de subdomain takeover. O arquivo JSON gerado e o state desta raiz não devem ser enviados ao controle de versão.

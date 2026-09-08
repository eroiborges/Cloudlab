# Handoff de DNS para o Route 53

Este diretório é uma raiz Terraform independente. Ele lê o objeto `handoff` gerado pelo deployment da Azure Web App e cria os registros TXT e CNAME em uma hosted zone pública existente no Route 53.

O handoff atual usa a zona pública `eroicloud.com.br` e contém:

- TXT `asuid.appdemo.eroicloud.com.br` para validar a propriedade do domínio no Azure App Service.
- CNAME `appdemo.eroicloud.com.br` apontando para o hostname padrão da Web App.

Esta configuração não cria nem altera a hosted zone. O Terraform apenas consulta a zona pública existente e gerencia os registros descritos no handoff.

## Pré-requisitos

- Terraform disponível no WSL.
- Credenciais AWS configuradas no ambiente WSL.
- Hosted zone pública `eroicloud.com.br` já existente no Route 53.
- Permissão para listar hosted zones e alterar registros nessa zona.
- Arquivo `../custom-domain/pilot.auto.tfvars.json` gerado pela raiz Terraform da infraestrutura Azure.

A identidade AWS precisa de permissões equivalentes a:

- `route53:ListHostedZonesByName`
- `route53:GetHostedZone`
- `route53:ChangeResourceRecordSets`
- `route53:GetChange`

## Validar a configuração

A partir deste diretório no WSL:

```bash
terraform init
terraform fmt -check
terraform validate
```

## Revisar o plano

Passe explicitamente o JSON gerado pela infraestrutura Azure como arquivo de variáveis. O Terraform não carrega automaticamente um arquivo `auto.tfvars.json` localizado em outro diretório.

```bash
terraform plan \
  -var-file=../custom-domain/pilot.auto.tfvars.json \
  -out=route53.tfplan
```

Revise o plano e confirme que ele cria somente os registros TXT e CNAME esperados.

## Aplicar

```bash
terraform apply route53.tfplan
```

## Validar o DNS público

Aguarde o Route 53 publicar a alteração e valide os registros usando um resolvedor público:

```bash
dig TXT asuid.appdemo.eroicloud.com.br @1.1.1.1
dig CNAME appdemo.eroicloud.com.br @1.1.1.1
```

O valor TXT retornado deve corresponder ao item `app-service-domain-verification` do handoff. O CNAME deve apontar para o hostname padrão da Web App.

## Continuar o deployment no Azure

Depois que os dois registros resolverem publicamente, ative o custom domain usando sua raiz Terraform independente:

```bash
cd ../custom-domain
terraform init
terraform validate
terraform plan -var="dns_validation_confirmed=true" -out=custom-domain.tfplan
terraform apply custom-domain.tfplan
```

Mantenha o registro TXT de verificação enquanto o custom domain estiver em uso para reduzir o risco de subdomain takeover.

## State e ciclo de vida

Este diretório possui seu próprio state Terraform. Em produção, configure um backend remoto protegido em vez de usar state local.

Ordem de desmontagem:

1. Destrua a raiz Terraform `custom-domain`.
2. Destrua esta raiz `route53` caso os registros DNS também devam ser removidos.
3. Destrua a raiz da infraestrutura Azure.

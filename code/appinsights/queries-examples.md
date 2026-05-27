# Exemplo de queries úteis para Application Insights

## Queries de Performance

### Tempo de resposta médio por endpoint
```kusto
requests
| where timestamp > ago(24h)
| summarize avg_duration = avg(duration), count = count() by name
| order by avg_duration desc
```

### Top 10 requisições mais lentas
```kusto
requests
| where timestamp > ago(24h)
| top 10 by duration desc
| project timestamp, name, duration, resultCode, url
```

## Queries de Erros

### Erros por tipo nos últimos 7 dias
```kusto
exceptions
| where timestamp > ago(7d)
| summarize count = count() by type, outerMessage
| order by count desc
```

### Taxa de erro por hora
```kusto
requests
| where timestamp > ago(24h)
| summarize 
    total_requests = count(),
    error_requests = countif(toint(resultCode) >= 400)
    by bin(timestamp, 1h)
| extend error_rate = (error_requests * 100.0) / total_requests
| render timechart
```

## Queries de Métricas Customizadas

### Receita total por hora (Northwind)
```kusto
customMetrics
| where name == "northwind_revenue_total"
| where timestamp > ago(24h)
| summarize total_revenue = sum(value) by bin(timestamp, 1h)
| render timechart
```

### Taxa de conversão de carrinho
```kusto
customEvents
| where name in ("Product_Added_To_Cart", "Demo_Scenario_Complete")
| where timestamp > ago(24h)
| summarize 
    cart_additions = countif(name == "Product_Added_To_Cart"),
    successful_orders = countif(name == "Demo_Scenario_Complete" and customDimensions.success == "true")
| extend conversion_rate = (successful_orders * 100.0) / cart_additions
```

## Queries de Usuário

### Usuários únicos por página
```kusto
pageViews
| where timestamp > ago(7d)
| summarize unique_users = dcount(user_Id) by name
| order by unique_users desc
```

### Jornada do usuário (funil)
```kusto
customEvents
| where timestamp > ago(24h) and name in ("Homepage_Card_Click", "Product_Added_To_Cart", "Demo_Scenario_Complete")
| summarize count = count() by name
| order by count desc
```

## Queries de Dependências

### Tempo de resposta do PostgreSQL
```kusto
dependencies
| where type == "SQL" and target contains "postgres"
| where timestamp > ago(24h)
| summarize avg_duration = avg(duration), count = count() by data
| order by avg_duration desc
```

### Falhas de dependências
```kusto
dependencies
| where success == false
| where timestamp > ago(7d)
| summarize count = count() by type, target, resultCode
| order by count desc
```

## Queries de Load Testing

### Throughput durante teste de carga
```kusto
requests
| where timestamp between (datetime(2024-01-25T10:00:00) .. datetime(2024-01-25T11:00:00))
| summarize requests_per_minute = count() by bin(timestamp, 1m)
| render timechart
```

### Impacto do teste de carga na performance
```kusto
requests
| where timestamp > ago(2h)
| summarize 
    avg_duration = avg(duration),
    p95_duration = percentile(duration, 95),
    count = count()
    by bin(timestamp, 5m)
| render timechart
```

## Alertas Recomendados

### Alta taxa de erro
```kusto
requests
| where timestamp > ago(5m)
| summarize 
    total = count(),
    errors = countif(toint(resultCode) >= 400)
| extend error_rate = (errors * 100.0) / total
| where error_rate > 5  // Alerta se taxa de erro > 5%
```

### Tempo de resposta elevado
```kusto
requests
| where timestamp > ago(5m)
| summarize avg_duration = avg(duration)
| where avg_duration > 5000  // Alerta se tempo médio > 5s
```

### Exceções não tratadas
```kusto
exceptions
| where timestamp > ago(5m)
| where type != "SimulatedJavaScriptError"  // Exclui erros simulados
| summarize count = count()
| where count > 0
```
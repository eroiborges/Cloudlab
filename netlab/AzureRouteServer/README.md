# BGP Lab Topology

Este diagrama descreve a topologia final do ambiente BGP com três roteadores (FRRouting) em VMs Ubuntu no Azure.

## Topologia Geral

```text
+-------------------+    +-------------------+    +-------------------+
|   Router 1        |    |   Router 2        |    |   Router 3        |
|   AS 65001        |    |   AS 65002        |    |   AS 65003        |
| IP: 10.150.0.10   |    | IP: 10.150.0.12   |    | IP: 10.160.0.4    |
| Net: 10.150.2.0/25|    | Net:10.150.2.128/25|   | Net: 10.160.0.0/26|
+-------------------+    +-------------------+    +-------------------+
          |                       |                       |
          |                       |                       |
          +-----------------------+-----------------------+
```

## Configuração BGP

### Router 1 (AS 65001)

- **Vizinho:** 10.150.0.12 (Router 2)
- **Redes anunciadas:**
  - 10.10.10.0/24
  - 10.150.2.0/25

### Router 2 (AS 65002)

- **Vizinhos:**
  - 10.150.0.10 (Router 1)
  - 10.160.0.4 (Router 3 via eBGP-multihop)
- **Redes anunciadas:**
  - 10.20.10.0/24
  - 10.150.2.128/25

### Router 3 (AS 65003)

- **Vizinho:** 10.150.0.12 (Router 2 via eBGP-multihop)
- **Redes anunciadas:**
  - 10.160.0.0/20 (via rota estática ou ajuste para /26)

## Características Técnicas

- **FRRouting versão:** 8.1
- **Modo:** frr defaults traditional
- **Política:** route-map PERMIT-ALL aplicada para IN/OUT
- **eBGP-multihop:** habilitado entre Router 2 e Router 3 (TTL=2)
- **Rotas estáticas:** adicionadas para garantir NHT (Next Hop Tracking)

## Fluxo de Configuração

1. Instalar FRR e habilitar BGP
2. Configurar vizinhos e redes
3. Aplicar route-map PERMIT-ALL
4. Ativar address-family ipv4 unicast
5. Adicionar rotas estáticas para vizinhos remotos
6. Validar com:

```bash
show ip bgp summary
show ip bgp
show ip bgp neighbors <IP> advertised-routes
```

## Diagrama Lógico

```text
Router 1 (AS65001) ---- Router 2 (AS65002) ---- Router 3 (AS65003)
10.150.0.10             10.150.0.12            10.160.0.4
```

### Peering

- **R1 ↔ R2:** eBGP direto
- **R2 ↔ R3:** eBGP-multihop (TTL=2)

## Observações

⚠️ **Importante:**

- Certifique-se de liberar TCP 179 nos NSGs
- Em peering entre VNets, habilitar "Allow forwarded traffic" nos dois lados
- Ajustar prefixos anunciados conforme redes locais

## **Tabela de Estados BGP**
| Estado        | Significado                                                                 |
|---------------|-----------------------------------------------------------------------------|
| **Idle**      | Sessão não iniciada. O roteador aguarda para tentar conexão.              |
| **Connect**   | Tentando abrir conexão TCP (porta 179) com o vizinho.                     |
| **Active**    | Tentativa de conexão falhou, aguardando nova tentativa.                   |
| **OpenSent**  | Conexão TCP estabelecida, enviou mensagem OPEN ao vizinho.                |
| **OpenConfirm**| Recebeu OPEN do vizinho, aguardando KEEPALIVE para confirmar sessão.     |
| **Established**| Sessão BGP ativa, troca de rotas acontecendo.                            |

---

## **Atributos BGP e Função**
| **Atributo**      | **Significado**                                                                 | **Impacto na Seleção de Caminho** |
|--------------------|---------------------------------------------------------------------------------|------------------------------------|
| **Origin**         | Como a rota foi originada no AS: `i` (IGP via network), `e` (EGP), `?` (incomplete) | Usado como critério final (i < e < ?) |
| **AS_PATH**        | Lista dos AS atravessados pela rota                                            | Quanto menor, melhor (evita loops) |
| **Next-Hop**       | IP do próximo salto para alcançar a rede                                       | Deve ser alcançável para instalar |
| **Local Preference**| Preferência local dentro do AS (padrão 100)                                   | Maior valor = mais preferido       |
| **MED (Multi-Exit Discriminator)**| Sugere preferência para entrada em outro AS (padrão 0)          | Menor valor = mais preferido       |
| **Weight**         | Atributo proprietário (Cisco/FRR), só local                                    | Maior valor = mais preferido       |
| **Community**      | Marca rotas para aplicar políticas (ex.: no-export, local-as)                  | Não influencia diretamente no best path |
| **Atomic Aggregate**| Indica agregação de rotas                                                     | Informativo                        |

---

### **Ordem de decisão do BGP (simplificada)**
1. **Weight** (maior é melhor)
2. **Local Preference** (maior é melhor)
3. **AS_PATH** (menor é melhor)
4. **Origin** (i < e < ?)
5. **MED** (menor é melhor)
6. Preferência por eBGP vs iBGP (eBGP ganha)
7. Menor IGP cost para next-hop
8. Menor Router-ID
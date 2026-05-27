# BGP Lab Topology & Troubleshooting Guide

Este documento descreve a topologia final do ambiente BGP com três roteadores (FRRouting) em VMs Ubuntu no Azure, incluindo scripts e boas práticas.
 
---

## **Topologia Geral**
```
           +-------------------+                +-------------------+                +-------------------+
           |   Router 1       |                |   Router 2       |                |   Router 3       |
           |   AS 65001       |                |   AS 65002       |                |   AS 65003       |
           | IP: 10.150.0.10  |                | IP: 10.150.0.12  |                | IP: 10.160.0.4   |
           | Net: 10.150.2.0/25|               | Net: 10.150.2.128/25|             | Net: 10.160.0.0/26|
           +-------------------+                +-------------------+                +-------------------+
                     |                                   |                                   |
                     |                                   |                                   |
                     +-----------------------------------+-----------------------------------+
```

---

## **Configuração BGP por Roteador**

### **Router 1 (AS 65001)**
```bash
router bgp 65001
 bgp router-id 10.150.0.10
 neighbor 10.150.0.12 remote-as 65002
 address-family ipv4 unicast
  neighbor 10.150.0.12 activate
  neighbor 10.150.0.12 route-map PERMIT-ALL in
  neighbor 10.150.0.12 route-map PERMIT-ALL out
  network 10.10.10.0/24
  network 10.150.2.0/25
 exit-address-family
```

### **Router 2 (AS 65002)**
```bash
router bgp 65002
 bgp router-id 10.150.0.12
 neighbor 10.150.0.10 remote-as 65001
 neighbor 10.160.0.4 remote-as 65003
 neighbor 10.160.0.4 ebgp-multihop 2
 address-family ipv4 unicast
  neighbor 10.150.0.10 activate
  neighbor 10.150.0.10 route-map PERMIT-ALL in
  neighbor 10.150.0.10 route-map PERMIT-ALL out
  neighbor 10.160.0.4 activate
  neighbor 10.160.0.4 route-map PERMIT-ALL in
  neighbor 10.160.0.4 route-map PERMIT-ALL out
  network 10.20.10.0/24
  network 10.150.2.128/25
 exit-address-family
```

### **Router 3 (AS 65003)**
```bash
router bgp 65003
 bgp router-id 10.160.0.4
 neighbor 10.150.0.12 remote-as 65002
 neighbor 10.150.0.12 ebgp-multihop 2
 address-family ipv4 unicast
  neighbor 10.150.0.12 activate
  neighbor 10.150.0.12 route-map PERMIT-ALL in
  neighbor 10.150.0.12 route-map PERMIT-ALL out
  network 10.160.0.0/20
 exit-address-family
```

---

## **Troubleshooting Checklist**

### ✅ 1. Rota no Kernel para vizinho (NHT)
- **Por quê?** FRR precisa de rota válida para o vizinho.
- **Validar:**  
  ```bash
  ip route show | grep <neighbor-IP>
  ```
- **Corrigir:**  
  ```bash
  sudo ip route add <neighbor-IP> via <gateway>
  ```

### ✅ 2. Prefixo anunciado deve existir no kernel
- **Por quê?** `network <prefix>` só anuncia se a rota existir.
- **Validar:**  
  ```bash
  ip route show | grep <prefix>
  ```
- **Corrigir:**  
  ```bash
  sudo ip addr add <IP>/<mask> dev <interface>
  ```

### ✅ 3. Necessidade do `neighbor activate`
- **Por quê?** Sem isso, não troca rotas.
- **Validar:**  
  ```bash
  show running-config | grep activate
  ```

### ✅ 4. Route-map obrigatório no modo `frr defaults traditional`
- **Por quê?** Sem política, aparece `(Policy)` no summary.
- **Validar:**  
  ```bash
  show ip bgp neighbors <IP>
  ```
- **Corrigir:**  
  ```bash
  route-map PERMIT-ALL permit 10
  neighbor <IP> route-map PERMIT-ALL in
  neighbor <IP> route-map PERMIT-ALL out
  ```

### ✅ 5. Porta TCP 179 liberada
- **Validar:**  
  ```bash
  telnet <neighbor-IP> 179
  ```

### ✅ 6. eBGP-multihop
- **Por quê?** Necessário para vizinhos não diretamente conectados.
- **Validar:**  
  ```bash
  show running-config | grep ebgp-multihop
  ```

### ✅ 7. VNet Peering no Azure
- **Por quê?** Para tráfego entre VNets, habilitar “Allow forwarded traffic” nos dois lados.
- **Validar:**  
  ```bash
  az network vnet peering show --name <peering-name> --vnet-name <vnet-name>
  ```

---

## **Validação Final**
```bash
show ip bgp summary
show ip bgp
show ip bgp neighbors <IP> advertised-routes
ip route show
```

---

## **Observações para Azure**
- Liberar TCP 179 nos NSGs.
- Habilitar “Allow forwarded traffic” nos dois lados do peering.
- Ajustar prefixos anunciados conforme redes locais.

---

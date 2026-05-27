#!/bin/bash
# Script para configurar Ubuntu como router/proxy NAT
# Interfaces: eth0 (untrust/internet), eth1 (trust/rede interna)

set -e

# Variáveis - ajuste conforme necessário
IF_UNTRUST="eth0"   # Interface conectada à Internet (ex: nic-fw-untrust)
IF_TRUST="eth1"     # Interface conectada à rede interna (ex: nic-fw-trust)

# Ativar IP forwarding
sysctl -w net.ipv4.ip_forward=1
sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

# Limpar regras antigas
iptables -F
iptables -t nat -F

# Habilitar NAT (masquerade) para saída pela interface untrust
iptables -t nat -A POSTROUTING -o "$IF_UNTRUST" -j MASQUERADE

# Permitir encaminhamento entre as interfaces
iptables -A FORWARD -i "$IF_TRUST" -o "$IF_UNTRUST" -j ACCEPT
iptables -A FORWARD -i "$IF_UNTRUST" -o "$IF_TRUST" -m state --state RELATED,ESTABLISHED -j ACCEPT

# (Opcional) Bloquear tráfego de entrada inesperado na interface untrust
# iptables -A INPUT -i "$IF_UNTRUST" -m state --state NEW -j DROP

# Salvar regras para persistência
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
else
    apt-get update && apt-get install -y iptables-persistent
    netfilter-persistent save
fi

echo "NAT e roteamento configurados com sucesso!"

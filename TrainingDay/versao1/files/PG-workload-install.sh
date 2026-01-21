
#!/usr/bin/env bash
# pg_install_lab.sh - Azure VM Extension (Linux) - Oracle Linux 10 + PGDG + PostgreSQL 16 (LAB)
# Idempotente, sem prompts, com log.
set -euo pipefail

LOG_FILE="/var/log/pg_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[$(date +%F\ %T)] Início do script de instalação PostgreSQL LAB"

# =========================
# Parâmetros (customizáveis)
# =========================
NET_CIDR="${NET_CIDR:-10.150.0.0/24}"
PGDATA="${PGDATA:-/var/lib/pgsql/16/data}"
SERVICE="${SERVICE:-postgresql-16}"
NORTHWIND_URL="${NORTHWIND_URL:-https://raw.githubusercontent.com/eroiborges/Cloudlab/refs/heads/main/TrainingDay/versao1/files/northwind.sql}"
NORTHWIND_SQL="/var/lib/pgsql/northwind.sql"

echo "[INFO] NET_CIDR=$NET_CIDR PGDATA=$PGDATA SERVICE=$SERVICE"

# =========================
# Instala repositório PGDG e pacotes
# =========================
echo "[INFO] Instalando repositório PGDG (EL-10)..."
dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-10-x86_64/pgdg-redhat-repo-latest.noarch.rpm

echo "[INFO] Verificando repositórios PGDG..."
mapfile -t repo_ids < <(dnf repolist 2>/dev/null | awk 'BEGIN{skip=1} /repo id/{next} NF && $1 !~ /^Last/ && $1 !~ /^repo/ {print $1}')
have_common=0; have_pgdg16=0
for r in "${repo_ids[@]}"; do
  [[ "$r" == "pgdg-common" ]] && have_common=1
  [[ "$r" == "pgdg16"      ]] && have_pgdg16=1
done
if (( !have_common || !have_pgdg16 )); then
  echo "[ERRO] Repositórios PGDG ausentes. Encontrados: ${repo_ids[*]:-<nenhum>}"
  exit 1
fi
echo "[OK] Repositórios PGDG ok: pgdg-common + pgdg16"

echo "[INFO] Instalando PostgreSQL 16 + utilitários..."
dnf -y install postgresql16-server postgresql16 git php php-pgsql httpd curl

# =========================
# Firewall
# =========================
echo "[INFO] Ajustando firewall (5432/tcp)..."
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=5432/tcp || true
  firewall-cmd --reload || true
else
  echo "[WARN] firewall-cmd não encontrado, pulando."
fi

# =========================
# initdb (apenas se necessário)
# =========================
if [[ -f "${PGDATA}/PG_VERSION" ]]; then
  echo "[INFO] Cluster já inicializado em ${PGDATA}"
else
  echo "[INFO] Inicializando cluster com initdb..."
  /usr/pgsql-16/bin/postgresql-16-setup initdb
fi

# =========================
# Serviço
# =========================
echo "[INFO] Habilitando e iniciando serviço ${SERVICE}..."
systemctl enable --now "${SERVICE}"

# =========================
# Configurar acesso remoto (listen + pg_hba)
# =========================
echo "[INFO] Configurando listen_addresses='*'..."
sed -i "s|^#\?listen_addresses.*|listen_addresses = '*'|" "${PGDATA}/postgresql.conf"

echo "[INFO] Configurando pg_hba.conf para rede ${NET_CIDR} (trust - LAB)..."
# Remove qualquer regra antiga com o mesmo NET_CIDR e insere no topo
sed -i "\|${NET_CIDR}|d" "${PGDATA}/pg_hba.conf"
sed -i "1ihost    all    all    ${NET_CIDR}    trust" "${PGDATA}/pg_hba.conf"

echo "[INFO] Reiniciando serviço para aplicar listen e recarregando HBA..."
systemctl restart "${SERVICE}"
systemctl reload  "${SERVICE}" || true

# =========================
# SELinux (HTTPD -> DB em LAB)
# =========================
if command -v setsebool >/dev/null 2>&1; then
  echo "[INFO] Ajustando SELinux boolean httpd_can_network_connect_db=1 (LAB)..."
  setsebool -P httpd_can_network_connect_db 1 || true
fi

# =========================
# Northwind (download e carga)
# =========================
echo "[INFO] Baixando Northwind SQL..."
curl -fsSL "${NORTHWIND_URL}" -o "/tmp/northwind.sql"
install -o postgres -g postgres -m 0644 /tmp/northwind.sql "${NORTHWIND_SQL}"

# =========================
# Usuários e banco (IDEMPOTENTE)
# =========================
echo "[INFO] Garantindo usuários e database (idempotente)..."
# demouser
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'demouser') THEN
    CREATE ROLE demouser LOGIN PASSWORD 'demopass123';
  ELSE
    ALTER ROLE demouser WITH LOGIN PASSWORD 'demopass123';
  END IF;
END
\$\$;"

# rootuser (superuser)
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rootuser') THEN
    CREATE ROLE rootuser LOGIN SUPERUSER;
  END IF;
  ALTER ROLE rootuser WITH PASSWORD '123rootpass456';
END
\$\$;"


# northwind DB (fora de DO; idempotente no shell)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='northwind'" | grep -q 1; then
  echo "[INFO] Criando database northwind (owner=demouser)..."
  sudo -u postgres createdb -O demouser northwind
else
  echo "[INFO] Database northwind já existe; seguindo."
fi

# Carga Northwind (só se vazio)
echo "[INFO] Carregando Northwind se necessário..."
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='customers';" northwind | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d northwind -f "${NORTHWIND_SQL}"
else
  echo "[INFO] Northwind já possui dados; pulando carga."
fi

# Grants e defaults
echo "[INFO] Aplicando GRANTs..."
sudo -u postgres psql -d northwind -v ON_ERROR_STOP=1 -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO demouser;"
sudo -u postgres psql -d northwind -v ON_ERROR_STOP=1 -c "GRANT SELECT, USAGE ON ALL SEQUENCES IN SCHEMA public TO demouser;"
sudo -u postgres psql -d northwind -v ON_ERROR_STOP=1 -c "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO demouser;"

echo "[INFO] Defaults (futuros objetos)..."
sudo -u postgres psql -d northwind -v ON_ERROR_STOP=1 -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO demouser;"
sudo -u postgres psql -d northwind -v ON_ERROR_STOP=1 -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, USAGE ON SEQUENCES TO demouser;"
sudo -u postgres psql -d northwind -v ON_ERROR_STOP=1 -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO demouser;"

echo "[OK] Finalizado com sucesso."
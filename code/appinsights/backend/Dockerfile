# Dockerfile para o Backend Python FastAPI - Multi-stage build otimizado
FROM python:3.11-alpine AS builder

# Instala dependências de build temporárias
RUN apk add --no-cache --virtual .build-deps \
    gcc \
    musl-dev \
    postgresql-dev \
    libffi-dev \
    openssl-dev

# Instala dependências Python
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# =======================================
# Imagem final de produção
FROM python:3.11-alpine AS production

# Instala apenas dependências de runtime (muito menores)
RUN apk add --no-cache \
    postgresql-libs \
    libffi \
    && rm -rf /var/cache/apk/*

# Cria usuário não-root
RUN adduser -D -s /bin/sh appuser

# Define diretório de trabalho
WORKDIR /app

# Copia dependências Python do builder
COPY --from=builder /root/.local /home/appuser/.local

# Copia apenas código fonte necessário
COPY main.py .
COPY services.py .
COPY database.py .
COPY models.py .

# Ajusta PATH para encontrar os pacotes instalados
ENV PATH=/home/appuser/.local/bin:$PATH

# Define ownership e usuário
RUN chown -R appuser:appuser /app
USER appuser

# Expose da porta
EXPOSE 8000

# Health check otimizado
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=2 \
    CMD wget --quiet --tries=1 --spider http://localhost:8000/health || exit 1

# Comando padrão
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
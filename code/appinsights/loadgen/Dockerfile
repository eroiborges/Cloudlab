# Dockerfile para Load Generator
FROM python:3.11-alpine

# Instala dependências do sistema
RUN apk add --no-cache gcc musl-dev

# Define diretório de trabalho
WORKDIR /app

# Copia requirements primeiro para melhor cache das layers
COPY requirements.txt .

# Instala dependências Python
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copia arquivos da aplicação
COPY . .

# Cria usuário não-root para segurança
RUN adduser -D -s /bin/sh loaduser && \
    chown -R loaduser:loaduser /app
USER loaduser

# Expose da porta do Locust Web UI
EXPOSE 8089

# Comando padrão - executa Locust com Web UI
CMD ["python", "-m", "locust", "-f", "locustfile.py", "--host", "http://northwind-backend-service:8000"]
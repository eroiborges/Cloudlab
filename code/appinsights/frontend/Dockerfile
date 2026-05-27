# Dockerfile multi-stage para Frontend React

# Stage 1: Build da aplicação React
FROM node:18-alpine AS builder

WORKDIR /app

# Copia package.json e package-lock.json (se existir)
COPY package*.json ./

# Instala todas as dependências (incluindo devDependencies para o build)
RUN npm install --silent

# Copia código fonte
COPY . .

# Build da aplicação para produção
RUN npm run build

# Stage 2: Servidor Nginx para servir arquivos estáticos
FROM nginx:1.25-alpine

# Instala curl para o healthcheck e gettext para envsubst
RUN apk add --no-cache curl gettext

# Remove configuração padrão do nginx
RUN rm -rf /usr/share/nginx/html/*

# Cria diretórios necessários para o nginx com permissões corretas
RUN mkdir -p /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp \
    /var/run \
    /var/log/nginx \
    && chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx \
    && chmod -R 755 /var/cache/nginx /var/run /var/log/nginx

# Copia arquivos do build
COPY --from=builder /app/build /usr/share/nginx/html

# Copia configuração customizada do nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copia e configura o script de entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expõe porta 8080
EXPOSE 8080

# Healthcheck para verificar se o nginx está respondendo
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/ || exit 1

# Comando padrão do nginx com entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
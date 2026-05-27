#!/bin/sh

# Define valores padrão se as variáveis não estiverem definidas
export API_BASE_URL=${API_BASE_URL:-http://localhost:8000}
export APPINSIGHTS_CONNECTION_STRING=${APPINSIGHTS_CONNECTION_STRING:-}

# Substitui as variáveis no index.html
envsubst '${API_BASE_URL} ${APPINSIGHTS_CONNECTION_STRING}' < /usr/share/nginx/html/index.html > /tmp/index.html
mv /tmp/index.html /usr/share/nginx/html/index.html

# Inicia o nginx
exec "$@"
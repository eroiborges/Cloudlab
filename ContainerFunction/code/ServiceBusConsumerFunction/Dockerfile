# Azure Functions runtime for Python 3.12
FROM mcr.microsoft.com/azure-functions/python:4-python3.12

# Azure Functions and pip configuration
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    PIP_INDEX_URL=https://packagefeedproxy.microsoft.io/pypi/simple \
    PIP_TRUSTED_HOST=packagefeedproxy.microsoft.io \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Update the system certificate store and install basic diagnostic tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Optional corporate root certificate:
# 1. Place the certificate beside this Dockerfile as corp-root-ca.crt
# 2. Uncomment the following lines
# COPY corp-root-ca.crt /usr/local/share/ca-certificates/corp-root-ca.crt
# RUN update-ca-certificates

# Configure pip to use the approved Microsoft package feed
RUN python -m pip config set global.index-url "${PIP_INDEX_URL}" && \
    python -m pip config set global.trusted-host "${PIP_TRUSTED_HOST}"

# Copy dependencies separately to improve Docker layer caching
COPY requirements.txt /tmp/requirements.txt

# Update pip tooling and install application dependencies
RUN python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install --requirement /tmp/requirements.txt && \
    rm -f /tmp/requirements.txt

# Copy the Azure Functions application
COPY . /home/site/wwwroot

WORKDIR /home/site/wwwroot


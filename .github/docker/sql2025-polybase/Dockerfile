FROM mcr.microsoft.com/mssql/server:2025-latest

USER root

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends apt-transport-https curl gnupg2 ca-certificates \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --batch --yes --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list \
        -o /etc/apt/sources.list.d/mssql-server-2025.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends mssql-server-polybase \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER mssql

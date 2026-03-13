FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        curl \
        gcc \
        g++ \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Build context = src/ingestion/ (cohérent avec CI ingestion-ci.yml)
COPY requirements.txt /tmp/requirements.txt

RUN python -m pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt

COPY . /workspace/

# INGESTION_SOURCE sélectionne le script à lancer (france_travail | sirene | geo)
# Injecté via env var Cloud Run Job ou --env au docker run
ENV INGESTION_SOURCE=france_travail

CMD ["sh", "-c", "python ingest_${INGESTION_SOURCE}.py"]

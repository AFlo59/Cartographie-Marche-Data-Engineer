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

# Build context = src/ingestion/ (coherent with CI workflows)
COPY requirements.txt /tmp/requirements.txt

RUN python -m pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt

COPY . /workspace/

# Source selector injected by Cloud Run Job override or docker --env
ENV INGESTION_SOURCE=france_travail

# Exécution directe depuis /workspace — les fichiers sont copiés à la racine du contexte src/ingestion/
CMD ["sh", "-c", "python main.py --source ${INGESTION_SOURCE}"]

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# Copy only package manifests — dbt deps layer cached independently from model/macro changes
COPY packages.yml dbt_project.yml profiles.yml ./
RUN dbt deps --project-dir /app --profiles-dir /app

COPY . .

ENV DBT_PROFILES_DIR=/app

CMD ["sh", "-c", "dbt run && dbt test"]

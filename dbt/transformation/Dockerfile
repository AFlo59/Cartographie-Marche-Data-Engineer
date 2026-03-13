FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./requirements.txt
RUN pip install --upgrade pip && pip install --no-cache-dir -r requirements.txt

COPY . .
RUN dbt deps --project-dir /app --profiles-dir /app

ENV DBT_PROFILES_DIR=/app

CMD ["sh", "-c", "dbt run && dbt test"]

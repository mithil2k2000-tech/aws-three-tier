# syntax=docker/dockerfile:1
FROM python:3.13-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim
ARG APP_VERSION=dev
ARG BREAK_HEALTHCHECK=false
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 APP_VERSION=$APP_VERSION BREAK_HEALTHCHECK=$BREAK_HEALTHCHECK
RUN apt-get update && apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --no-create-home app
COPY --from=build /install /usr/local
WORKDIR /srv
COPY src ./src
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s CMD python -c "import urllib.request,sys;sys.exit(urllib.request.urlopen('http://127.0.0.1:8000/api/healthz').status!=200)"
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header", "--proxy-headers"]

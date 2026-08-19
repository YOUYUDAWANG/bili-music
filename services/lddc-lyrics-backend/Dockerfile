FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git libglib2.0-0 libgl1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml NOTICE.md README.md ./
COPY lddc_backend ./lddc_backend
RUN pip install --no-cache-dir .

ENV LDDC_BACKEND_HOST=0.0.0.0
ENV LDDC_BACKEND_PORT=8788
EXPOSE 8788

CMD ["bilimusic-lddc-backend"]


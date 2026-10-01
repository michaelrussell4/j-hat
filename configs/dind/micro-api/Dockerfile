FROM python:3.11-alpine

WORKDIR /app

# Install postgres dependency build tools
RUN apk add --no-cache libpq

COPY requirements.txt .
RUN apk add --no-cache --virtual .build-deps gcc musl-dev postgresql-dev && \
    pip install --no-cache-dir -r requirements.txt && \
    apk del .build-deps

COPY app.py .

EXPOSE 8000

CMD ["python", "app.py"]

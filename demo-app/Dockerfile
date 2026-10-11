# Imagen mínima: solo Python estándar, sin dependencias externas.
FROM python:3.13-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app.py .

# Usuario sin privilegios (la plataforma además exige runAsNonRoot)
RUN adduser -D -u 10001 nimbus
USER 10001

EXPOSE 8080
CMD ["python", "app.py"]

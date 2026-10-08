# Small base image (tag is mutable; no digest pin). python:3.12-slim keeps the attack surface low
# compared with the full python image (~1 GB -> ~150 MB).
FROM python:3.12-slim

# Do not run the API as root: if the process is ever compromised, the
# attacker lands as an unprivileged user inside the container.
RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /var/log/campuspulse \
    && chown appuser:appuser /var/log/campuspulse

WORKDIR /srv/app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py seed_users.py manage_user.py ./

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]

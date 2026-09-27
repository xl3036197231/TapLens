FROM docker.m.daocloud.io/library/python@sha256:392307d22300de8b5986851a12d9176dfc0fc073e65bf6523ebd7dcbeb23564e

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright

WORKDIR /srv/taplens/backend

COPY backend/requirements-deploy.txt ./

RUN sed -i \
    -e 's|http://deb.debian.org/debian-security|https://mirrors.aliyun.com/debian-security|g' \
    -e 's|http://deb.debian.org/debian|https://mirrors.aliyun.com/debian|g' \
    /etc/apt/sources.list.d/debian.sources

RUN pip install --no-cache-dir -r requirements-deploy.txt \
    && python -m playwright install-deps chromium \
    && python -m playwright install chromium-headless-shell

COPY backend/app ./app
COPY backend/scripts ./scripts

RUN mkdir -p /var/lib/taplens/artifacts

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]

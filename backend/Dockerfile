FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --system recovery \
    && useradd --system --gid recovery recovery \
    && mkdir /data && chown recovery:recovery /data
COPY app.py recovery.py mailer.py serve.py ./
COPY static ./static
ENV PORT=8787 RECOVERY_DATABASE=/data/recovery.db PYTHONUNBUFFERED=1
USER recovery
EXPOSE 8787
CMD ["python", "serve.py"]

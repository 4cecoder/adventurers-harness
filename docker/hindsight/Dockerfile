FROM python:3.11-slim
WORKDIR /app
COPY server.py /app/server.py
EXPOSE 8888
HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8888/health')" || exit 1
CMD ["python3", "server.py"]

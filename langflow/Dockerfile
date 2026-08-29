# Langflow, built locally: the upstream image plus the Python packages the
# class uses inside Langflow components (requirements.txt) and uv, so
# `./kingo langflow ...` can manage packages with real uv commands.
# Same local-build pattern as jupyterhub/ — pull/bundle/load know both.
FROM langflowai/langflow:1.8.0
COPY requirements.txt /tmp/kingo-requirements.txt
# The image's PATH puts /app/.venv/bin first, so this pip installs into the
# exact virtualenv Langflow imports from.
RUN pip install --no-cache-dir uv -r /tmp/kingo-requirements.txt

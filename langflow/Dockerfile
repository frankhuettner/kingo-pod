# Langflow, built locally: the upstream image plus the Python packages the
# class uses inside Langflow components and uv, so `./kingo langflow ...` can
# manage packages with real uv commands.
# Same local-build pattern as jupyterhub/ — pull/bundle/load know both.
#
# Two package files. class-requirements.txt: what the class gets, maintained
# here. requirements.txt: frozen at its v1.4.0 content, because students add
# their own packages to it, and git cannot pull past a file both sides changed
# (class-requirements.txt says more).
FROM langflowai/langflow:1.8.0
COPY class-requirements.txt requirements.txt /tmp/kingo/
# The image's PATH puts /app/.venv/bin first, so this pip installs into the
# exact virtualenv Langflow imports from.
RUN pip install --no-cache-dir uv -r /tmp/kingo/class-requirements.txt -r /tmp/kingo/requirements.txt
# The class packages import, and so does transformers (see the huggingface-hub
# pin), or the build fails here rather than in a flow (as on release-1.5).
RUN python -c "import ragas, statsmodels.api, nemoguardrails, transformers"

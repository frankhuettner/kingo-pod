# Langflow, built locally: the upstream image plus the Python packages the
# class uses inside Langflow components (requirements.txt). The image ships
# uv, which `./kingo langflow ...` uses to manage packages.
# Same local-build pattern as jupyterhub/ — pull/bundle/load know both.
FROM langflowai/langflow:1.12.4
COPY requirements.txt /tmp/kingo-requirements.txt
COPY excludes.txt /tmp/kingo-excludes.txt
COPY vertexai-stub.py /tmp/vertexai-stub.py
# Since 1.12 the base (UBI) puts a second virtualenv on PATH, /opt/app-root
# with its own pip, so a bare `pip install` can land where Langflow never
# imports from. Name Langflow's interpreter explicitly.
RUN uv pip install --no-cache --python /app/.venv/bin/python \
      --excludes /tmp/kingo-excludes.txt -r /tmp/kingo-requirements.txt
# ragas 0.4.3, its last release, imports langchain_community.chat_models.vertexai,
# which langchain-community 0.4 removed. ragas only uses ChatVertexAI in
# isinstance checks, so an empty class is exact.
RUN set -e; \
    d="$(/app/.venv/bin/python -c 'import os, langchain_community.chat_models as m; print(os.path.dirname(m.__file__))')"; \
    if [ ! -e "$d/vertexai.py" ]; then cp /tmp/vertexai-stub.py "$d/vertexai.py"; fi
# Two components importing the openai SDK in parallel threads deadlock on the
# first run after a start; the .pth imports it at interpreter start instead
# (the file explains — including when to delete it). Copied this late so that
# editing it does not redo the package install above.
COPY kingo-preload.pth /tmp/kingo-preload.pth
RUN cp /tmp/kingo-preload.pth "$(/app/.venv/bin/python -c 'import sysconfig; print(sysconfig.get_path("purelib"))')/"
# A class package that cannot import fails the build (and CI), not a student's
# flow — and so does a preload that stopped running (checked first: ragas
# imports openai itself).
RUN /app/.venv/bin/python -c "import sys; assert 'openai.resources' in sys.modules, 'kingo-preload.pth did not run'; import ragas, statsmodels.api, nemoguardrails"

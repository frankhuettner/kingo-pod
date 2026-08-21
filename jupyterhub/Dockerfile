# JupyterHub with the single-user Lab in the SAME container: the official hub
# image ships only the hub + proxy, and the docker-stacks notebook images ship
# no proxy — neither runs a classroom hub alone. Built locally (tagged
# kingo-jupyterhub:local), so `<engine> compose pull` must skip it
# (--ignore-buildable) and `kingo update` rebuilds it explicitly.
FROM quay.io/jupyterhub/jupyterhub:5
RUN python3 -m pip install --no-cache-dir jupyterlab notebook
COPY jupyterhub_config.py /etc/jupyterhub/jupyterhub_config.py
CMD ["jupyterhub", "-f", "/etc/jupyterhub/jupyterhub_config.py"]

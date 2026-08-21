# Classroom JupyterHub: any username + the shared class password logs in and
# gets its own Lab. Everything runs inside one container as one OS user, so
# the "simple" spawner (per-user process + home dir) is the right fit — real
# system users would buy nothing on a single-student laptop.
import os

c.JupyterHub.authenticator_class = 'dummy'
c.DummyAuthenticator.password = os.environ.get('DUMMY_PASSWORD', 'kingo2026')
c.Authenticator.allow_all = True
c.Authenticator.admin_users = {'student'}

c.JupyterHub.spawner_class = 'simple'
# Home dirs + hub db live under /srv/jupyterhub, which compose mounts as a
# named volume — notebooks survive restarts and image updates.
c.SimpleLocalProcessSpawner.home_dir_template = '/srv/jupyterhub/homes/{username}'
c.JupyterHub.cookie_secret_file = '/srv/jupyterhub/jupyterhub_cookie_secret'
c.JupyterHub.db_url = 'sqlite:////srv/jupyterhub/jupyterhub.sqlite'

c.Spawner.default_url = '/lab'
# The container runs as root and the simple spawner keeps that user; the
# single-user server refuses to start as root unless told otherwise.
c.Spawner.args = ['--allow-root']

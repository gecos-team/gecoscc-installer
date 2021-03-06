[app:gecoscc]

#
# Please, check https://github.com/gecos-team/gecoscc-ui/blob/development/config-templates/development.ini
# and do not forget to include latest changes
#

# Monitoring parameters
server_name = ${HOSTNAME}
server_ip = ${GECOS_CC_SERVER}

# This pattern must be http[s]://<user>:<password>@%s:<port>/RPC2
# Internally %s will be replaced by server IP
# user and password must match the ones in supervisord.conf
supervisord.url.pattern = http://${SUPERVISOR_USER_NAME}:${SUPERVISOR_PASSWORD}@%s:9001/RPC2

# This pattern could be HTTP or HTTPS depending on your configuration
gecos.internal.url.pattern = http://%s/internal/server/%s

use = egg:gecoscc

pyramid.reload_templates = true
pyramid.debug_authorization = false
pyramid.debug_notfound = false
pyramid.debug_routematch = false
pyramid.debug_templates = false
pyramid.default_locale_name = en
pyramid.locales = ["en", "es"]

jinja2.directories = gecoscc:templates
jinja2.filters =
    admin_jsonify = gecoscc.filters.admin_serialize
    datetime = gecoscc.filters.datetime
    regex_match = gecoscc.filters.regex_match

mongo_uri = ${MONGO_URL}

#session.type = memory
session.type = file
session.data_dir = %(here)s/sessions/data
session.lock_dir = %(here)s/sessions/lock
session.key = session
session.secret = 12341234
session.cookie_on_exception = true

# Chef version number (in X.Y.Z format)
chef.version = 12.14.0
chef.url = ${CHEF_SERVER_URL}
chef.cookbook_name = gecos_ws_mgmt
chef.seconds_sleep_is_busy = 5
chef.seconds_block_is_busy = 3600
# smart_lock_sleep_factor is use to avoid concurrency problem
# We use this parameter to sleep the process between GET and POST request.
# It's a temporary solution 
chef.smart_lock_sleep_factor = 3
# ssl_verify is used to avoid urllib3 ssl certificate validation
chef.ssl.verify = False

# CELERY (using redis backend)
celery_broker_url = redis://localhost:6379/4

# SOCKETS (using redis backend)
sockjs_url = redis://localhost:6379/0

firstboot_api.version = 0.2.0
firstboot_api.organization_name = ${ORGANIZATION}
firstboot_api.media = %(here)s/../gecoscc/media/users
firstboot_api.gem_repo = ${RUBY_GEMS_REPOSITORY_URL}

help_manual_url = ${HELP_URL}

update_error_interval = 24

repositories = ["http://v2.gecos.guadalinex.org/gecos/", "http://v2.gecos.guadalinex.org/ubuntu/", "http://v2.gecos.guadalinex.org/mint/"]

printers.urls = ["http://www.openprinting.org/download/foomatic/foomatic-db-nonfree-current.tar.gz",
                "http://www.openprinting.org/download/foomatic/foomatic-db-current.tar.gz"]

software_profiles =
    {
    "Office": ["libreoffice", "libreoffice-gnome","evince","libreoffice-java-common","libreoffice-officebean"],
    "Remote Support": ["xrdp", "x11vnc"]
    }

mimetypes = [ "image/jpeg", "image/png", "application/pdf", "application/zip", "application/rar", "video/mp4" ]


# Updates
# Add trailing slash when is a directory
updates.dir = /opt/gecoscc/updates/
updates.tmp = /tmp/
updates.log = %(updates.dir)s/{0}/update.log
updates.control = %(updates.dir)s/{0}/control
updates.scripts = %(updates.dir)s/{0}/scripts/
updates.cookbook = %(updates.dir)s/{0}/cookbook/
updates.backups = %(updates.dir)s/{0}/backups/
updates.rollback = %(updates.dir)s/{0}/rollback.log
updates.chef_backup = /opt/gecoscc/scripts/chef_backup.sh
updates.chef_restore = /opt/gecoscc/scripts/chef_restore.sh
config_uri  = %(here)s/gecoscc.ini

# Idle time (seconds)
# On maintenance mode, this parameter filters active users
idle_time = 900



[pipeline:main]
pipeline =
    translogger
    gecoscc

[filter:translogger]
use = egg:Paste#translogger
setup_console_handler = False

[server:main]
use = egg:gunicorn#main
host = 0.0.0.0
port = %(http_port)s
workers = 4
# Choose between a proxy safe worker class 
# worker_class = gevent
# Or this websockets worker (better user interaction and ui refresh)
worker_class = gecoscc.socks.GecosGeventSocketIOWorker
timeout = 600

# Begin logging configuration

[loggers]
keys = root, gecoscc

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = INFO
handlers = console

[logger_gecoscc]
level = DEBUG
handlers =
qualname = gecoscc

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(asctime)s %(levelname)-5.5s [%(name)s][%(threadName)s] %(message)s

# End logging configuration

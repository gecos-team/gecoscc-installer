FROM python:2.7.9

ARG GECOSCC_VERSION=2.5.0 
ARG GECOSCC_LANG=es_ES.UTF-8
ARG DISTRIBUTION=jessie
ARG CHEF_CLIENT_URL=https://packages.chef.io/files/stable/chef/12.22.5/debian/8/chef_12.22.5-1_amd64.deb
ARG CHEF_SERVER_VERSION
ARG CHEF_SERVER_URL

RUN printf "deb http://archive.debian.org/debian/ $DISTRIBUTION main\ndeb-src http://archive.debian.org/debian/ $DISTRIBUTION main\ndeb http://security.debian.org $DISTRIBUTION/updates main\ndeb-src http://security.debian.org $DISTRIBUTION/updates main" > /etc/apt/sources.list
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y locales lsof unzip   

# Install Chef client
RUN wget $CHEF_CLIENT_URL -O /tmp/chef.deb && dpkg -i /tmp/chef.deb && rm  /tmp/chef.deb

# Set language to Spanish
RUN sed -i -e 's/# es_ES.UTF-8/es_ES.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG $GECOSCC_LANG
ENV LC_ALL $GECOSCC_LANG  

# Install GECOS CC
RUN pip install --upgrade https://github.com/gecos-team/gecoscc-ui/archive/$GECOSCC_VERSION.zip

# Fixing gevent-socketio error
RUN sed -i 's/"Access-Control-Max-Age", 3600/"Access-Control-Max-Age", "3600"/'  /usr/local/lib/python2.7/site-packages/socketio/handler.py \
	&& sed -i 's/"Access-Control-Max-Age", 3600/"Access-Control-Max-Age", "3600"/'  /usr/local/lib/python2.7/site-packages/socketio/transports.py

# Create GECOS CC user
# (42 is the uid of "hab" user inside Chef server machines.
#  By using this uid the gecoscc user will have permission to read the config
#  files).
RUN useradd -u 42 -d /opt/gecosccui -r -s /bin/false gecoscc

# Create working directories
RUN mkdir -p /opt/gecosccui/ && chown gecoscc /opt/gecosccui \
	&& mkdir -p /opt/gecoscc/ && chown gecoscc /opt/gecoscc \
	&& mkdir -p /logs/gecoscc/ && chown gecoscc /logs/gecoscc \
	&& mkdir -p /opt/gecosccui/.chef/ && chown gecoscc /opt/gecosccui/.chef 

# Copy gecoscc.ini and replace values
COPY gecoscc.ini /opt/gecosccui/ 
RUN  sed -i "s|CHEF_SERVER|$CHEF_SERVER_URL|"  /opt/gecosccui/gecoscc.ini \
	&& sed -i "s|CHEF_VERSION|$CHEF_SERVER_VERSION|"  /opt/gecosccui/gecoscc.ini \
	&& chown gecoscc /opt/gecosccui/gecoscc.ini

# Copy knife.rb and replace values
COPY knife.rb /opt/gecosccui/.chef
RUN  sed -i "s|CHEF_SERVER|$CHEF_SERVER_URL|"  /opt/gecosccui/.chef/knife.rb \
	&& chown gecoscc /opt/gecosccui/.chef/knife.rb


USER gecoscc
WORKDIR /opt/gecosccui/

CMD ["pserve", "/opt/gecosccui/gecoscc.ini", "http_port=8010"]



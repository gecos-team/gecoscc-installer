FROM debian:buster-slim

#ARG GECOSCC_VERSION=2.5.0 
ARG GECOSCC_VERSION=development
ARG GECOSCC_LANG=es_ES.UTF-8
ARG REPOSITORY_URL=http://deb.debian.org/debian/
ARG DISTRIBUTION=buster
ARG CHEF_CLIENT_URL=https://packages.chef.io/files/stable/chef/12.22.5/debian/8/chef_12.22.5-1_amd64.deb
ARG CHEF_SERVER_VERSION
ARG CHEF_SERVER_URL
ARG CHEF_SERVER_INTERNAL_URL
ARG SUPERVISOR_USER_NAME=internal
ARG SUPERVISOR_PASSWORD=changeme
ARG MONGODB_URL

RUN printf "deb $REPOSITORY_URL $DISTRIBUTION main\ndeb-src $REPOSITORY_URL $DISTRIBUTION main\ndeb $REPOSITORY_URL $DISTRIBUTION-updates main\ndeb-src $REPOSITORY_URL $DISTRIBUTION-updates main\ndeb http://security.debian.org/debian-security/ $DISTRIBUTION/updates main\n" > /etc/apt/sources.list
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y locales lsof unzip mongo-tools gettext wget build-essential libreadline-dev zlib1g-dev flex bison libxml2-dev libxslt-dev libxml2-utils xsltproc libgetoptions-dev libssl-dev python3.7 python3.7-venv python3-pip

# Install Chef client
RUN wget $CHEF_CLIENT_URL -O /tmp/chef.deb && dpkg -i /tmp/chef.deb && rm  /tmp/chef.deb

# Install the knife-ec-backup GEM
COPY knife-ec-backup-2.4.3.gem /tmp/
RUN mkdir /tmp/build \
	&& cd /tmp/build \
	&& wget http://ftp.postgresql.org/pub/source/v9.2.8/postgresql-9.2.8.tar.gz \
	&& tar -zxf postgresql-9.2.8.tar.gz \
	&& cd postgresql-9.2.8 \
	&& export MAJOR_VER=9.2 \
    && LD_LIBRARY_PATH=/opt/chef/embedded/lib ./configure   --prefix=/opt/chef/embedded \
		--mandir=/opt/chef/embedded/share/postgresql/${MAJOR_VER}/man \
		--docdir=/opt/chef/embedded/share/doc/postgresql-doc-${MAJOR_VER} \
		--sysconfdir=/etc/postgresql-common \
		--datarootdir=/opt/chef/embedded/share/ \
		--datadir=/opt/chef/embedded/share/postgresql/${MAJOR_VER} \
		--bindir=/opt/chef/embedded/lib/postgresql/${MAJOR_VER}/bin \
		--libdir=/opt/chef/embedded/lib/ \
		--libexecdir=/opt/chef/embedded/lib/postgresql/ \
		--includedir=/opt/chef/embedded/include/postgresql/ \
		--enable-nls   --enable-integer-datetimes   --enable-thread-safety \
		--enable-debug   --with-gnu-ld   --with-pgport=5432   --with-openssl \
		--with-libedit-preferred \
		--with-includes=/opt/chef/embedded/include \
		--with-libs=/opt/chef/embedded/lib \
	&& make \
	&& make install \
	&& /opt/chef/embedded/bin/gem install pg -- --with-pg-config=/opt/chef/embedded/lib/postgresql/9.2/bin/pg_config \
	&& /opt/chef/embedded/bin/gem install /tmp/knife-ec-backup-2.4.3.gem \
	&& rm -rf /tmp/build

# Set language to Spanish
RUN sed -i -e 's/# es_ES.UTF-8/es_ES.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG $GECOSCC_LANG
ENV LC_ALL $GECOSCC_LANG  

# Install supervisor GECOS CC
#RUN pip install supervisor \
#	&& pip install --upgrade https://github.com/gecos-team/gecoscc-ui/archive/$GECOSCC_VERSION.zip

RUN pip3 install supervisor \
	&& pip3 install --upgrade https://github.com/System25/gecoscc-ui/archive/v3.zip


# Fix python 3.8 errors in PyChef
#RUN sed -i "10,15d" /usr/local/lib/python3.8/site-packages/chef/rsa.py \
#    && sed -i 's/        _eay/    _eay/'  /usr/local/lib/python3.8/site-packages/chef/rsa.py

# Fix a weird python 3 error that causes pyramid beaker to get stuck when
# trying persist sessions information in MongoDB
RUN sed -i "47 a \ \ \ \ \ \ \ \ self.db.collection_names()" \
     /usr/local/lib/python3.7/dist-packages/beaker/ext/mongodb.py

# Fixing gevent-socketio error
#RUN sed -i 's/"Access-Control-Max-Age", 3600/"Access-Control-Max-Age", "3600"/'  /usr/local/lib/python2.7/site-packages/socketio/handler.py \
#	&& sed -i 's/"Access-Control-Max-Age", 3600/"Access-Control-Max-Age", "3600"/'  /usr/local/lib/python2.7/site-packages/socketio/transports.py

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
RUN  sed -i "s|CHEF_SERVER_INTERNAL_URL|$CHEF_SERVER_INTERNAL_URL|"  /opt/gecosccui/gecoscc.ini \
    && sed -i "s|CHEF_SERVER|$CHEF_SERVER_URL|"  /opt/gecosccui/gecoscc.ini \
	&& sed -i "s|CHEF_VERSION|$CHEF_SERVER_VERSION|"  /opt/gecosccui/gecoscc.ini \
	&& sed -i "s|GECOSCC_VERSION|$GECOSCC_VERSION|"  /opt/gecosccui/gecoscc.ini \
	&& sed -i "s|MONGODB_URL|$MONGODB_URL|"  /opt/gecosccui/gecoscc.ini \
	&& chown gecoscc /opt/gecosccui/gecoscc.ini


# Copy supervisord.conf and replace values
COPY supervisord.conf /opt/gecosccui/ 
RUN  sed -i "s|SUPERVISOR_USER_NAME|$SUPERVISOR_USER_NAME|"  /opt/gecosccui/supervisord.conf\
	&& sed -i "s|SUPERVISOR_PASSWORD|$SUPERVISOR_PASSWORD|"  /opt/gecosccui/supervisord.conf\
	&& chown gecoscc /opt/gecosccui/supervisord.conf


# Copy knife.rb and replace values
COPY knife.rb /opt/gecosccui/.chef
RUN  sed -i "s|CHEF_SERVER|$CHEF_SERVER_URL|"  /opt/gecosccui/.chef/knife.rb \
	&& chown gecoscc /opt/gecosccui/.chef/knife.rb

USER gecoscc
WORKDIR /opt/gecosccui/

CMD ["supervisord", "-n", "-c", "/opt/gecosccui/supervisord.conf"]


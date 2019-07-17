FROM python:2.7.9

ARG GECOSCC_VERSION=2.5.0 
ARG GECOSCC_LANG=es_ES.UTF-8

RUN printf "deb http://archive.debian.org/debian/ jessie main\ndeb-src http://archive.debian.org/debian/ jessie main\ndeb http://security.debian.org jessie/updates main\ndeb-src http://security.debian.org jessie/updates main" > /etc/apt/sources.list
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y locales lsof
RUN sed -i -e 's/# es_ES.UTF-8/es_ES.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG $GECOSCC_LANG
ENV LC_ALL $GECOSCC_LANG  

RUN pip install --upgrade https://github.com/gecos-team/gecoscc-ui/archive/$GECOSCC_VERSION.zip

# Fixing gevent-socketio error
RUN sed -i 's/"Access-Control-Max-Age", 3600/"Access-Control-Max-Age", "3600"/'  /usr/local/lib/python2.7/site-packages/socketio/handler.py
RUN sed -i 's/"Access-Control-Max-Age", 3600/"Access-Control-Max-Age", "3600"/'  /usr/local/lib/python2.7/site-packages/socketio/transports.py

RUN useradd -d /opt/gecosccui -r -s /bin/false gecoscc
RUN mkdir -p /opt/gecosccui/ && chown gecoscc /opt/gecosccui
RUN mkdir -p /opt/gecoscc/ && chown gecoscc /opt/gecoscc
RUN mkdir -p /logs/gecoscc/ && chown gecoscc /logs/gecoscc

COPY gecoscc.ini /opt/gecosccui/ 
RUN  chown gecoscc /opt/gecosccui/gecoscc.ini

USER gecoscc
WORKDIR /opt/gecosccui/

CMD ["pserve", "/opt/gecosccui/gecoscc.ini", "http_port=8010"]



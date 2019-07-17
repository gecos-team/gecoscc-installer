FROM nginx:1.10.2
RUN rm /etc/nginx/nginx.conf
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/
COPY gecoscc.conf /etc/nginx/sites-enabled/


FROM chefserverofficial/chef-server-nginx:12.18.14

ARG DEFAULT_ORG_NAME

RUN sed -i "s/--   config.set_default_org(false)/    config.set_default_org(\"$DEFAULT_ORG_NAME\")/" \
 /hab/pkgs/jeremymv2/chef-server-nginx/12.18.14/20181017193855/config/nginx.conf 

 



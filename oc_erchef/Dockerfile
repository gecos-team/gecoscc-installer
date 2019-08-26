FROM chefserverofficial/oc_erchef:12.18.14

ARG DEFAULT_ORG_NAME

RUN sed -i "s/{default_orgname, undefined },/{default_orgname, <<\"$DEFAULT_ORG_NAME\">> },/" \
 /hab/pkgs/jeremymv2/oc_erchef/12.18.14/20181017195230/config/sys.config



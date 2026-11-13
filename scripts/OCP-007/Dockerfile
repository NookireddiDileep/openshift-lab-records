FROM registry.access.redhat.com/ubi9/httpd-24
LABEL maintainer="Nookireddi Dileep" \
      description="app-04: custom static site on UBI9 httpd" \
      version="1.0"
# copy my content into httpd's document root
COPY index.html /var/www/html/index.html
# random-UID friendly: group 0 owns it and can read/write (OpenShift runs us as a random UID in group 0)
USER 0
RUN chgrp -R 0 /var/www/html && chmod -R g=u /var/www/html
USER 1001
EXPOSE 8080

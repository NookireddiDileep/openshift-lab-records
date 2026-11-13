FROM docker.io/library/busybox:1.36
LABEL maintainer="Nookireddi Dileep" description="test-app: tiny static site on busybox httpd" version="1.0"
COPY index.html /www/index.html
RUN chgrp -R 0 /www && chmod -R g=u /www
USER 1001
EXPOSE 8080
CMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]

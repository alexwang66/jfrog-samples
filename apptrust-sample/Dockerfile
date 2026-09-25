ARG NGINX_IMAGE=solenglatest.jfrog.io/alex-docker/nginx:latest
FROM ${NGINX_IMAGE}
USER root
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget --spider -q http://127.0.0.1:3000/healthz || exit 1

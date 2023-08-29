FROM hashicorp/consul-template:0.20.0-scratch as consul-template1
FROM prom/alertmanager:v0.25.0

# Get dumb-init 
RUN wget --no-check-certificate -O /home/dumb-init \
    https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 && \
    chmod +x /home/dumb-init

# Copy consul-template from consul-template image
COPY --from=consul-template1 /consul-template /bin/consul-template

# Copy consul-template configuration
COPY ./config.hcl /consul-template/config.hcl

# Copy Prometheus configuration file template
COPY ./alertmanager/config.yml.ctpl /etc/alertmanager/config.yml.ctpl

ENTRYPOINT ["/home/dumb-init", "--"]

CMD ["/bin/consul-template", "-config=/consul-template/config.hcl"]
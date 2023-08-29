# Dynamic configuration AM

## 1 . Dynamic configuration AM

- chuẩn bị
    - `image prom/prometheus` và `prom/alertmanager` image  nó sẽ là images đễ build một container Prometheus và AM
    - `consul-template` dùng để cập nhật file config `prometheus.yml` đến contianer Prometheus
    - **`dumb-init**` giúp chạy tiển trình `consul-template` bên trong container, và sau đó sẽ chạy container sau khi đã cập nhật file

### 1.1 **consul-template**

- [consul-template](https://github.com/hashicorp/consul-template?ref=0x63.me) is a tool from HashiCorp, which *queries a Consul or Vault cluster and updates any number of specified templates on the file system. As an added bonus, it can optionally run arbitrary commands when the update process completes. (có thể hiểu như sau* có nghĩa là sử dụng công cụ **`consul-template`** để tạo cấu hình cho Prometheus trong môi trường Docker một cách tự động và linh hoạt*)*
- **`consul-template`** sẽ kết nối đến một cụm Consul hoặc nguồn dữ liệu khác để lấy thông tin về các mục tiêu cần giám sát.
- Dựa trên dữ liệu này, **`consul-template`** sẽ tạo ra một tệp **`config.yml`** mới hoặc cập nhật tệp cấu hình hiện có với các mục tiêu mới.

Trong thử nghiệm sau sẽ cần 2 loại file :

- Configuration file for consul-template
- Prometheus file to fill in

1.2.1 **configuration file**

```jsx
exec {
  command       = "/bin/alertmanager --config.file=/etc/alertmanager/config.yml --web.listen-address=:9093 --log.level=info"

  reload_signal = "SIGHUP"
  kill_signal   = "SIGTERM"
  kill_timeout  = "15s"
}

template {
  source      = "/etc/alertmanager/config.yml.ctpl"
  destination = "/etc/alertmanager/config.yml"
  perms       = 0640
}

```

có 3 trường quan trọng cần lưu ý là `command`, `source`, `destination` 

- `source`:  là đường dẫn đến template trong container. trong trường hợp đối với prometheus hay alermanager thì là đường dẫn đến file `config.yml.ctpl` ví dụ `/etc/alertmanager/config.yml.ctpl` file này đòng vai trò là mẫu (template) cho file cấu hình chính `config.yml.ctpl`
- `destination path` : là đường dẫn đến file cấu hình của prometheus, tức là đường dẫn đến file ``config.yml`` thực tế và sẽ được khởi tạo trong container
- `command` : Đây là lệnh sẽ được thực hiện sau khi mà `consul-template` đã khởi tạo các file cấu hình thành công, lệnh này thường là lệnh khởi tạo cho prometheus như là : --`config.file=/etc/prometheus/prometheus.yml`

### 1.2 ****dumb-init****

- Là một tiện ic để quản lý tiến trình đơn giản và tối ưu việc khởi tạo hệ thông. Nó cho phép chạy kếp hợp **consul-template** và **prometheus** trong cùng một container.
- Khi chạy ta sử dụng `dumb-init` như là một `ENTRYPOINT` cho prometheus container . Điều nay có nghĩa là khi container được khởi chạy, `dumb-init` sẽ được chạy như tiến trình cha đầu tiên được chạy sau đó nó sẽ quản lý quá trình chạy consul-template và khí consul-template hoàn tất nó sẽ khởi chạy prometheus

### 1.3 ****alermanager config.yml template****

template file `config.yml.ctpl` chuẩn bị cho `consul-template:`

```yaml

  inhibit_rules:
    - target_match:
        severity: "warning"
      source_match:
        severity: "critical"
      # Apply inhibition if the alertname and instance are the same.
      equal: ["alertname", "instance"]

  route:
    receiver: "all"
    group_interval: 30s
    repeat_interval: 30s

    routes:
      - match:
          alertname: high_memory_load
        receiver: "telegram"
        repeat_interval: {{ or (env "REPEAT_INTERVAL") "1m" }}
        continue: true

      - match:
          alertname: high_cpu_load
        receiver: "email"
        repeat_interval: {{ or (env "REPEAT_INTERVAL") "1m" }}
        continue: true

      - match:
          alertname: high_storage_load
        receiver: "slack"
        repeat_interval: {{ or (env "REPEAT_INTERVAL") "1m" }}
        continue: true
  receivers:
    - name: "all"
      slack_configs:
        - send_resolved: true
          text: "{{ .CommonAnnotations.description }}"
          username: "Prometheus"
          channel: "#test"
          api_url: {{ (env "INCOMMING_WEBHOOK") }}
      webhook_configs:
        - url: {{ (env "TELE_WEBHOOK") }}
          http_config:
      email_configs:
        - to: {{ (env "EMAIL_FIELD") }}
          from: 'goldf55f@gmail.com'
          smarthost: 'smtp.gmail.com:587'
          auth_username: 'goldf55f@gmail.com'
          auth_password: ''
      

    - name: "slack"
      slack_configs:
        - send_resolved: true
          text: "{{ .CommonAnnotations.description }}"
          username: "Prometheus"
          channel: "#test"
          api_url: {{ (env "INCOMMING_WEBHOOK") }}

    - name: "telegram"
      webhook_configs:
        - url: {{ (env "TELE_WEBHOOK") }}
          http_config:


    - name: "email"
      email_configs:
        - to: {{ (env "EMAIL_FIELD") }}
          from: 'goldf55f@gmail.com'
          smarthost: 'smtp.gmail.com:587'
          auth_username: 'goldf55f@gmail.com'
          auth_password: ''
```

### 1.4 Dockerfile

```docker
    FROM hashicorp/consul-template:0.20.0-scratch as consul-template1
    FROM prom/alertmanager:v0.25.0

    RUN wget --no-check-certificate -O /home/dumb-init \
        https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 && \
        chmod +x /home/dumb-init

    COPY --from=consul-template1 /consul-template /bin/consul-template
    COPY ./config.hcl /consul-template/config.hcl
    COPY ./alertmanager/config.yml.ctpl /etc/alertmanager/config.yml.ctpl
    ENTRYPOINT ["/home/dumb-init", "--"]

    CMD ["/bin/consul-template", "-config=/consul-template/config.hcl"]
```

### 1.5 docker-compose 

```yaml
    alertmanager1:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: alertmanager1
    restart: unless-stopped
    environment:
      - INCOMMING_WEBHOOK=https://hooks.slack.com/services/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
      - TELE_WEBHOOK=https://telepush.dev/api/inlets/alertmanager/008a95
      - EMAIL_FIELD=manhduc030402@gmail.com
    network_mode: host
    depends_on:
      - sms
```

### 1.6 Result 

Sau khi khôi chạy các service `alermanager` và ``prometheus`` ta dùng lệnh ``docker exec -it "container" sh`` để  `ssh` vào container đó, sau đó dùng lệnh ``cat /etc/alertmanager/config.yml`` để kiểm tra nội dung file ``config.yml``



<div align="center">
  <img src="assets/pic_1.png">
</div>

kết quả gửi cảnh báo thành công


<div align="center">
  <img width=200 src="assets/pic_2.png">
  <img width=200 src="assets/pic_3.png">
  <img width=200 src="assets/pic_4.jpeg">
</div>

# Dynamic configuration AM

## 1 . Dynamic configuration AM

- chuẩn bị
    - `image prom/prometheus` và `prom/**alertmanager`** image  nó sẽ là images đễ build một container Prometheus và AM
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
  command       = "/bin/**alertmanager --**config.file=/etc/**alertmanager/config**.yml --web.listen-address=:9093 --log.level=info"

  reload_signal = "SIGHUP"
  kill_signal   = "SIGTERM"
  kill_timeout  = "15s"
}

template {
  source      = "/etc/**alertmanager/config**.yml.ctpl"
  destination = "/etc/**alertmanager/config**.yml"
  perms       = 0640
}

```

có 3 trường quan trọng cần lưu ý là `command`, `source`, `destination` 

- `source`:  là đường dẫn đến template trong container. trong trường hợp đối với prometheus hay alermanager thì là đường dẫn đến file `config.yml.ctpl` ví dụ `/etc/**alertmanager/config**.yml.ctpl` file này đòng vai trò là mẫu (template) cho file cấu hình chính `config.yml.ctpl`
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



COMMENT 2 :

## Mapping config notification channel sử dụng consul key-value và consul template 

mapping config notification channel người dùng --> key/value trên consul --> config alertmanager

### Mô hình triển khai



<div align="center">
  <img src="https://github.com/LittleHawk03/markdown/assets/76674885/395412d3-7f2c-4d78-a958-32829adf0383">
</div>


### Thử nghiệm triển khai consul server để chạy consul key-value service

có thể deploy được consul server trên môi trường container bằng docker theo 2 cách sau 

docker run :

```sh
  docker run \                                        
    -d \
    -p 8500:8500 \
    -p 8600:8600/udp \
    --name=badger \
    consul:1.15.4 agent -server -ui -node=server-1 -bootstrap-expect=1 -client=0.0.0.0
```

docker-compose:


```yaml
    consul:
      image: consul:1.15.4
      container_name: consul_alert
      volumes:
        - ./keyvalue:/etc/tmp/
      command: 
        - "agent -server -ui -node=server-1 -bootstrap-expect=1 -client=0.0.0.0"
        - "./etc/tmp/consul_keyvalue.sh"
      ports:
        - 8500:8500
        - 8600:8600
      restart: unless-stopped
```

truy cập vào web ui của consul qua ip ``http://localhost:8500`` hoăc địa chỉ sau ``http://116.103.226.93:8500/`` (em built để thử nghiệm thôi ạ).

<div align="center">
  <img src="https://github.com/LittleHawk03/markdown/assets/76674885/a6cd12a0-769e-48f0-a8da-41230fc2c634">
</div>

**ssh** vào docker container của consul bằng lệnh `docker exec -it container_name sh` rồi chạy các lệnh sau để thêm các key-value:

```sh
  #webhook
  consul kv put alertmanager/config/webhook/alertname "tele_1"
  consul kv put alertmanager/config/webhook/url "https://telepush.dev/api/inlets/alertmanager/008a95"

  #slackconfiguration
  consul kv put alertmanager/config/slack/alertname "slack_1"
  consul kv put alertmanager/config/slack/api_url "https://hooks.slack.com/services/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"
  consul kv put alertmanager/config/slack/channel "#test"

  #mail
  consul kv put alertmanager/config/email/alertname "mail_1"
  consul kv put alertmanager/config/email/mail "manhduc030402@gmail.com"
```

sử dụng lệnh ``consul kv get alertmanager/config/email/alertname`` hoặc sử dụng web ui đển xem các key-value đã thêm.

<div align="center">
  <img src="https://github.com/LittleHawk03/markdown/assets/76674885/d3be911b-43d4-4db3-ac8c-322a298a81c5">
</div>

### Thử nghiệm dùng consul-template dynamic configuration của alertmanager

file config .hcl

```go
  consul{
    address = "116.103.226.93:8500"
  }

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

file template config.yml.ctpl

```yaml
route:
  receiver: "all"
  group_interval: 30s
  repeat_interval: 30s
  routes:
    - match:
        alertname: "{{ key "alertmanager/config/webhook/alertname" }}"
      receiver: "telegram"
      repeat_interval: 1m
      continue: true

    - match:
        alertname: "{{ key "alertmanager/config/slack/alertname" }}"
      receiver: "slack"
      repeat_interval: 1m
      continue: true

    - match:
        alertname: "{{ key "alertmanager/config/email/alertname" }}"
      receiver: "email"
      repeat_interval: 1m
      continue: true
receivers:
  - name: "all"
    webhook_configs:
      - url: '{{ key "alertmanager/config/webhook/url/" }}'
        http_config:

  - name: "slack"
    slack_configs:
      - send_resolved: true
        text: "{{ .CommonAnnotations.description }}"
        username: "Prometheus"
        channel: "{{ key "alertmanager/config/slack/channel" }}"
        api_url: "{{ key "alertmanager/config/slack/api_url" }}"

  - name: "telegram"
    webhook_configs:
      - url: '{{ key "alertmanager/config/webhook/url" }}'
        http_config:

  - name: "email"
    email_configs:
      - to: '{{ key "alertmanager/config/email/mail" }}'
        from: 'goldf55f@gmail.com'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'goldf55f@gmail.com'
        auth_password: ''
```

chạy lại file Dockerfile đã build sẵn như trên rồi truy cập vào trong container để xem file config.yaml

<div align="center">
  <img src="https://github.com/LittleHawk03/markdown/assets/76674885/d187b57e-e415-4875-bd1f-a563e6742cf1">
</div>

``cat config.yml``

<div align="center">
  <img src="https://github.com/LittleHawk03/markdown/assets/76674885/b03445e4-0259-42bc-9e61-f8113b8d12ff">
</div>

như ta thấy các field đã được dynamic đầy đủ 


Vấn đề em đang gặp phải em muốn thực hiện các biểu thức logic trong file template tuy nhiên thì nó đang bế tắc anh xem qua hộ em với ạ

## COMMENT 3

EM viết lại file template mới ạ


```yaml
  global:
  # The smarthost and SMTP sender used for mail notifications.
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'goldf55f@gmail.com'
  smtp_auth_username: 'goldf55f@gmail.com'
  # smtp_auth_identity: ''
  smtp_auth_password: 'cbpamuevasnbbnrb'
  # smtp_require_tls: false

inhibit_rules:
- target_match:
    severity: "warning"
  source_match:
    severity: "critical"
  # Apply inhibition if the alertname and instance are the same.
  equal: ["alertname", "instance"]

route:
  repeat_interval: 2h
  group_by: ['alertname']
  receiver: default
  group_wait: 60s
  group_interval: 5m

  routes:
{{ range $user_id, $pairs := tree "users/" | explode }}
  {{ range $alarm_type, $pairs := tree ($user_id | printf "users/%s/alarms/") | explode}}
    {{ range $alarm_id , $pairs := tree ($alarm_type | printf "users/%s/alarms/%s" $user_id) | explode}}
  - match:
      user_id: {{ $user_id }}
    receiver: '{{ $user_id }} - {{ $alarm_type }} - {{ $alarm_id }}'
    repeat_interval: 1h
    {{ end }}
  {{ end }}
{{ end }}

receivers:
  - name: default

{{ range $user_id, $pairs := tree "users/" | explode }}
  {{ range $alarm_type, $pairs := tree ($user_id | printf "users/%s/alarms/") | explode}}
    {{ range $alarm_id , $pairs := tree ($alarm_type | printf "users/%s/alarms/%s/" $user_id) | explode}}
        {{if eq $alarm_type "email" }}

  - name: '{{ $user_id }} - {{ $alarm_type }} - {{ $alarm_id }}'
    email_configs:
      - to: '{{ range ls ($alarm_id | printf "users/%s/alarms/email/%s" $user_id ) -}}{{if eq .Key "receiver"}}{{ scratch.Set .Key .Value }}{{end}}{{end}}{{scratch.Get "receiver"}}'
        send_resolved: true
        text: "CommonAnnotations.description "
        tls_config:
          insecure_skip_verify: true
        # html: '{{ `{{ template "email.viettel.html" . }}` }}'
        headers:
          subject: "CMP Alert"

        {{ else if eq $alarm_type "slack"}}
        
  - name: '{{ $user_id }} - {{ $alarm_type }} - {{ $alarm_id }}'
    slack_configs:
      - send_resolved: true
        text: "CommonAnnotations.description"
        username: '{{ range ls ($alarm_id | printf "users/%s/alarms/slack/%s" $user_id ) -}}{{if eq .Key "username"}}{{ scratch.Set .Key .Value }}{{end}}{{end}}{{scratch.Get "username"}}'
        channel: '{{ range ls ($alarm_id | printf "users/%s/alarms/slack/%s" $user_id ) -}}{{if eq .Key "channel"}}{{ scratch.Set .Key .Value }}{{end}}{{end}}{{scratch.Get "channel"}}'
        api_url: '{{ range ls ($alarm_id | printf "users/%s/alarms/slack/%s" $user_id ) -}}{{if eq .Key "api_url"}}{{ scratch.Set .Key .Value }}{{end}}{{end}}{{scratch.Get "api_url"}}'
        
        {{ else if eq $alarm_type "telegram"}}

  - name: '{{ $user_id }} - {{ $alarm_type }} - {{ $alarm_id }}'
    webhook_configs:
      - url: '{{ range ls ($alarm_id | printf "users/%s/alarms/telegram/%s" $user_id ) -}}{{if eq .Key "tele_webhook"}}{{ scratch.Set .Key .Value }}{{end}}{{end}}{{scratch.Get "tele_webhook"}}'
        http_config:

        {{ else if $alarm_type "webhook" }}

  - name: '{{ $user_id }} - {{ $alarm_type }} - {{ $alarm_id }}'
    webhook_configs:
      - url: '{{ range ls ($alarm_id | printf "users/%s/alarms/webhook/%s" $user_id ) -}}{{if eq .Key "url"}}{{ scratch.Set .Key .Value }}{{end}}{{end}}{{scratch.Get "url"}}'
        http_config:

        {{ else if $alarm_type "sms" }}

  - name : '{{ $user_id }} - {{ $alarm_type }} - {{ $alarm_id }}'
  
        {{ end }}
    {{ end }}
  {{ end }}
{{ end }}

 
templates:
- '/etc/alertmanager/template/viettel_email.tmpl'


```

bây giờ các lệnh put sẽ là 


```sh
  consul kv put /users/user_id/alarms/email/alarm_id/receiver
  # slack
  consul kv put /users/user_id/alarms/slack/alarm_id/username
  consul kv put /users/user_id/alarms/slack/alarm_id/channel
  consul kv put /users/user_id/alarms/slack/alarm_id/api_url
  #telegram
  consul kv put /users/user_id/alarms/telegram/alarm_id/tele_webhook 
  # webhook
  consul kv put /users/user_id/alarms/webhook/alarm_id/url
  # sms
  consul kv put /users/user_id/alarms/email/alarm_id/

```


## Metering notification channel

#### Mô hình như sau :

<div align="center">
  <img src="assets/pic_10.png">
</div>


#### Flow thực hiện như sau 

- Một con Prometheus sẽ làm nhiệm vụ thu thập các metric từ alertmanager 
- Bằng việc thu thập metric từ alertmanager từ đó metering được số tin nhắn đã được gửi thành công hay thất bại 
- Lưu các dữ liệu người dùng này vào một file ``.csv`` để có thể billing, file ``.csv`` vào sau khi người dùng thanh toán file này sẽ bị reset.

<div align="center">
  <img src="assets/pic_11.png">
</div>

#### vấn đề 

- do là protheus chỉ theo dõi là tin nhắn đã gửi đi như thế nào mà không phân biệt đâu là tin nhắn được gửi cho người dùng nào




- **alertmanager_alerts** How many alerts by state.
- **alertmanager_alerts_invalid_total** The total number of received alerts that were invalid.** counter
- **alertmanager_alerts_received_total** The total number of received alerts.** counter
- **alertmanager_build_info** A metric with a constant '1' value labeled by version, revision, branch, and goversion from which alertmanager was built.
- **alertmanager_cluster_alive_messages_total** Total number of received alive messages.
- **alertmanager_cluster_enabled** Indicates whether the clustering is enabled or not.
- **alertmanager_cluster_failed_peers** Number indicating the current number of failed peers in the cluster.
- **alertmanager_cluster_health_score** Health score of the cluster. Lower values are better and zero means 'totally healthy'.
- **alertmanager_cluster_members** Number indicating current number of members in cluster.

- **alertmanager_cluster_messages_pruned_total** Total number of cluster messages pruned.

- **alertmanager_cluster_messages_queued** Number of cluster messages which are queued.

- **alertmanager_cluster_messages_received_size_total** Total size of cluster messages received.

- **alertmanager_cluster_messages_received_total** Total number of cluster messages received.

- **alertmanager_cluster_messages_sent_size_total** Total size of cluster messages sent.

- **alertmanager_cluster_messages_sent_total** Total number of cluster messages sent.

- **alertmanager_cluster_peer_info** A metric with a constant '1' value labeled by peer name.

- **alertmanager_cluster_peers_joined_total** A counter of the number of peers that have joined.

- **alertmanager_cluster_peers_left_total** A counter of the number of peers that have left.

- **alertmanager_cluster_peers_update_total** A counter of the number of peers that have updated metadata.

- **alertmanager_cluster_reconnections_failed_total** A counter of the number of failed cluster peer reconnection attempts.

- **alertmanager_cluster_reconnections_total** A counter of the number of cluster peer reconnections.

- **alertmanager_cluster_refresh_join_failed_total** A counter of the number of failed cluster peer joined attempts via refresh.

- **alertmanager_cluster_refresh_join_total** A counter of the number of cluster peer joined via refresh.

- **alertmanager_config_hash** Hash of the currently loaded **alertmanager configuration**.

- **alertmanager_config_last_reload_success_timestamp_seconds** Timestamp of the last successful configuration reload.

- **alertmanager_config_last_reload_successful** Whether the last configuration reload attempt was successful.

- **alertmanager_dispatcher_aggregation_groups** Number of active aggregation groups

- **alertmanager_dispatcher_alert_processing_duration_seconds** Summary of latencies for the processing of alerts.

- **alertmanager_http_concurrency_limit_exceeded_total** Total number of times an HTTP request failed because the concurrency limit was reached.

- **alertmanager_http_request_duration_seconds** Histogram of latencies for HTTP requests.

- **alertmanager_http_requests_in_flight** Current number of HTTP requests being processed.

- **alertmanager_http_response_size_bytes** Histogram of response size for HTTP requests.


- **alertmanager_marked_alerts** How many alerts by state are currently marked in the **Alertmanager regardless** of their expiry.

- **alertmanager_nflog_gc_duration_seconds** Duration of the last notification log garbage collection cycle.

- **alertmanager_nflog_gossip_messages_propagated_total** Number of received gossip messages that have been further gossiped.

- **alertmanager_nflog_queries_total** Number of notification log queries were received.

- **alertmanager_nflog_query_duration_seconds** Duration of notification log query evaluation.

- **alertmanager_nflog_query_errors_total** Number notification log received queries that failed.

- **alertmanager_nflog_snapshot_duration_seconds** Duration of the last notification log snapshot.

- **alertmanager_nflog_snapshot_size_bytes** Size of the last notification log snapshot in bytes.

## metric về notification channel

- **alertmanager_notification_latency_seconds** The latency of notifications in seconds.

- **alertmanager_notification_requests_failed_total** The total number of failed notification requests.

- **alertmanager_notification_requests_total** The total number of attempted notification requests.

- **alertmanager_notifications_failed_total** The total number of failed notifications.

- **alertmanager_notifications_total** The total number of attempted notifications.

- **alertmanager_oversize_gossip_message_duration_seconds** Duration of oversized gossip message requests.

- **alertmanager_oversized_gossip_message_dropped_total** Number of oversized gossip messages that were dropped due to a full message queue.

- **alertmanager_oversized_gossip_message_failure_total** Number of oversized gossip message sends that failed.

- **alertmanager_oversized_gossip_message_sent_total** Number of oversized gossip message sent.

- **alertmanager_peer_position** Position the **Alertmanager instance** believes it's in. The position determines a peer's behavior in the cluster.

- **alertmanager_receivers** Number of configured receivers.

- **alertmanager_silences** How many silences by state.

- **alertmanager_silences_gc_duration_seconds** Duration of the last silence garbage collection cycle.

- **alertmanager_silences_gossip_messages_propagated_total** Number of received gossip messages that have been further gossiped.

- **alertmanager_silences_queries_total** How many silence queries were received.

- **alertmanager_silences_query_duration_seconds** Duration of silence query evaluation.

- **alertmanager_silences_query_errors_total** How many silence received queries did not succeed.

- **alertmanager_silences_snapshot_duration_seconds** Duration of the last silence snapshot.

- **alertmanager_silences_snapshot_size_bytes** Size of the last silence snapshot in bytes.

- **go_gc_duration_seconds** A summary of the pause duration of garbage collection cycles.

- **go_goroutines** Number of goroutines that currently exist.

- **go_info** Information about the Go environment.

- **go_memstats_alloc_bytes** Number of bytes allocated and still in use.

- **go_memstats_alloc_bytes_total** Total number of bytes allocated, even if freed.

- **go_memstats_buck_hash_sys_bytes** Number of bytes used by the profiling bucket hash table.

- **go_memstats_frees_total** Total number of frees.

- **go_memstats_gc_sys_bytes** Number of bytes used for garbage collection system metadata.

- **go_memstats_heap_alloc_bytes** Number of heap bytes allocated and still in use.

- **go_memstats_heap_idle_bytes** Number of heap bytes waiting to be used.

- **go_memstats_heap_inuse_bytes** Number of heap bytes that are in use.

- **go_memstats_heap_objects** Number of allocated objects.

- **go_memstats_heap_released_bytes** Number of heap bytes released to OS.

- **go_memstats_heap_sys_bytes** Number of heap bytes obtained from system.

- **go_memstats_last_gc_time_seconds** Number of seconds since 1970 of last garbage collection.

- **go_memstats_lookups_total** Total number of pointer lookups.

- **go_memstats_mallocs_total** Total number of mallocs.

- **go_memstats_mcache_inuse_bytes** Number of bytes in use by mcache structures.

- **go_memstats_mcache_sys_bytes** Number of bytes used for mcache structures obtained from system.

- **go_memstats_mspan_inuse_bytes** Number of bytes in use by mspan structures.

- **go_memstats_mspan_sys_bytes** Number of bytes used for mspan structures obtained from system.

- **go_memstats_next_gc_bytes** Number of heap bytes when next garbage collection will take place.

- **go_memstats_other_sys_bytes** Number of bytes used for other system allocations.

- **go_memstats_stack_inuse_bytes** Number of bytes in use by the stack allocator.

- **go_memstats_stack_sys_bytes** Number of bytes obtained from system for stack allocator.

- **go_memstats_sys_bytes** Number of bytes obtained from system.

- **go_threads** Number of OS threads created.

- **net_conntrack_dialer_conn_attempted_total** Total number of connections attempted by the given dialer a given name.

- **net_conntrack_dialer_conn_closed_total** Total number of connections closed which originated from the dialer of a given name.

- **net_conntrack_dialer_conn_established_total** Total number of connections successfully established by the given dialer a given name.

- **net_conntrack_dialer_conn_failed_total** Total number of connections failed to dial by the dialer a given name.

- **process_cpu_seconds_total** Total process

- **process_virtual_memory_max_bytes** Maximum amount of virtual memory available in bytes.

- **promhttp_metric_handler_requests_in_flight** Current number of scrapes being served.

- **promhttp_metric_handler_requests_total** Total number of scrapes by HTTP status code.


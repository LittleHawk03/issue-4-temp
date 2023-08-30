#webhook
consul kv put alertmanager/config/webhook/alertname "unique_name"
consul kv put alertmanager/config/webhook/url/ "https://sdadasd.com//"

#slackconfiguration
consul kv put alertmanager/config/slack/alertname "unique_name"
consul kv put alertmanager/config/slack/api_url "https://hooks.slack.com/services/your-slack-webhook-url"
consul kv put alertmanager/config/slack/channel "#test"

#mail
consul kv put alertmanager/config/email/alertname "unique_name"
consul kv put alertmanager/config/email/mail "abc@gmail.com"

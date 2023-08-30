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

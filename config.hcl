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

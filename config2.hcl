consul{
  address = "0.0.0.0:8500"
}

exec {
  command       = "/bin/alertmanager --config.file=/etc/alertmanager/config.yml --web.listen-address=0.0.0.0:9094 --cluster.listen-address=0.0.0.0:9096 --cluster.peer=0.0.0.0:9095 --log.level=info"
                    
  reload_signal = "SIGHUP"
  kill_signal   = "SIGTERM"
  kill_timeout  = "15s"
}

template {
  source      = "/etc/alertmanager/config.yml.ctpl"
  destination = "/etc/alertmanager/config.yml"
  perms       = 0640
}
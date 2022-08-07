stolen from:
[https://blog.cubieserver.de/2021/restic-backups-with-systemd-and-prometheus-exporter/](https://blog.cubieserver.de/2021/restic-backups-with-systemd-and-prometheus-exporter/)

this does a few things...
* uses a systemd timer for backups instead of a cron job.
* parses the backup log to post results to prometheus.
* emails on failure (;_;)

module.exports = {
  apps: [
    {
      name: "asf",
      script: "/opt/ops/scripts/pm2-run-asf.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/asf.out.log",
      error_file: "/opt/logs/asf.err.log",
      merge_logs: true
    },
    {
      name: "mcs-daemon",
      script: "/opt/ops/scripts/pm2-run-mcs-daemon.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/mcs-daemon.out.log",
      error_file: "/opt/logs/mcs-daemon.err.log",
      merge_logs: true
    },
    {
      name: "mcs-web",
      script: "/opt/ops/scripts/pm2-run-mcs-web.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/mcs-web.out.log",
      error_file: "/opt/logs/mcs-web.err.log",
      merge_logs: true
    },
    {
      name: "aria2",
      script: "/opt/ops/scripts/pm2-run-aria2.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/aria2.out.log",
      error_file: "/opt/logs/aria2.err.log",
      merge_logs: true
    },
    {
      name: "transmission",
      script: "/opt/ops/scripts/pm2-run-transmission.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/transmission.out.log",
      error_file: "/opt/logs/transmission.err.log",
      merge_logs: true
    },
    {
      name: "bt-trackers",
      script: "/opt/ops/scripts/pm2-run-bt-trackers.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/bt-trackers.out.log",
      error_file: "/opt/logs/bt-trackers.err.log",
      merge_logs: true
    },
    {
      name: "syncthing",
      script: "/opt/ops/scripts/pm2-run-syncthing.sh",
      interpreter: "none",
      uid: "syncthing",
      gid: "syncthing",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/syncthing.out.log",
      error_file: "/opt/logs/syncthing.err.log",
      merge_logs: true
    },
    {
      name: "filebrowser",
      script: "/opt/ops/scripts/pm2-run-filebrowser.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/filebrowser.out.log",
      error_file: "/opt/logs/filebrowser.err.log",
      merge_logs: true
    },
    {
      name: "direct-candidates",
      script: "/opt/ops/scripts/direct-candidates-server.py",
      interpreter: "python3",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/direct-candidates.out.log",
      error_file: "/opt/logs/direct-candidates.err.log",
      merge_logs: true
    },
    {
      name: "homeassistant",
      script: "/opt/ops/scripts/pm2-run-homeassistant.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      restart_delay: 5000,
      max_memory_restart: "1900M",
      env: {
        HASS_NICE_LEVEL: "10",
        HASS_OOM_SCORE_ADJ: "300",
        HASS_ENABLE_CGROUP_GUARD: "1",
        HASS_CGROUP_PATH: "/sys/fs/cgroup/opt-homeassistant",
        HASS_MEMORY_HIGH_BYTES: "1572864000",
        HASS_MEMORY_MAX_BYTES: "2147483648",
        HASS_MEMORY_SWAP_MAX_BYTES: "0"
      },
      out_file: "/opt/logs/homeassistant.out.log",
      error_file: "/opt/logs/homeassistant.err.log",
      merge_logs: true
    },
    {
      name: "caddy",
      script: "/opt/ops/scripts/pm2-run-caddy.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/caddy.out.log",
      error_file: "/opt/logs/caddy.err.log",
      merge_logs: true
    },
    {
      name: "tinyproxy",
      script: "/opt/ops/scripts/pm2-run-tinyproxy.sh",
      interpreter: "none",
      autorestart: true,
      max_restarts: 20,
      out_file: "/opt/logs/tinyproxy.out.log",
      error_file: "/opt/logs/tinyproxy.err.log",
      merge_logs: true
    }
  ]
};

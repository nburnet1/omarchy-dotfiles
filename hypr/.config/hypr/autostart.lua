-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Night light (constant 2700K) is handled by the enabled systemd user service:
--   systemctl --user status hyprsunset.service
-- See ~/.config/systemd/user/hyprsunset.service.d/override.conf

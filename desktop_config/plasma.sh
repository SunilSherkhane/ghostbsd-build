#!/bin/sh
#
# FreeBSD Plasma + LightDM live setup script
#

set -e -u

# Source common configuration scripts
. "${cwd}/common_config/autologin.sh"
. "${cwd}/common_config/base-setting.sh"
. "${cwd}/common_config/finalize.sh"
. "${cwd}/common_config/setuser.sh"

update_rcconf_dm() {
  rc_conf="${release}/etc/rc.conf"

  # Enable SDDM
  echo 'lightdm_enable="YES"' >> "${rc_conf}"
}

lightdm_setup() {
  lightdm_conf="${release}/usr/local/etc/lightdm/lightdm.conf"

  sed -i '' "s@#greeter-session=.*@greeter-session=slick-greeter@" "${lightdm_conf}"
  sed -i '' "s@#user-session=default@user-session=plasma@" "${lightdm_conf}"
}

set_localtime_from_bios() {
  tz_target="${release}/etc/localtime"

  rm -f "${tz_target}"

  ln -s /usr/share/zoneinfo/UTC "${tz_target}"

  rc_conf="${release}/etc/rc.conf"
  sed -i '' '/^ntpd_enable=.*/d' "${rc_conf}" 2>/dev/null || true
  sed -i '' '/^ntpd_sync_on_start=.*/d' "${rc_conf}" 2>/dev/null || true
  sed -i '' '/^local_unbound_enable=.*/d' "${rc_conf}" 2>/dev/null || true

  echo 'ntpd_enable="YES"' >> "${rc_conf}"
  echo 'ntpd_sync_on_start="YES"' >> "${rc_conf}"
}

plasma_settings() {
  sysctl_conf="${release}/etc/sysctl.conf"

  sed -i '' '/^net.local.stream.recvspace/d' "${sysctl_conf}" 2>/dev/null || true
  sed -i '' '/^net.local.stream.sendspace/d' "${sysctl_conf}" 2>/dev/null || true

  echo 'net.local.stream.recvspace=65536' >> "${sysctl_conf}"
  echo 'net.local.stream.sendspace=65536' >> "${sysctl_conf}"

  # Allow regular users to mount filesystems.
  echo 'vfs.usermount=1' >> "${sysctl_conf}"
}

setup_xinit() {
  # Configure Plasma session settings and fallback .xinitrc
  chroot "${release}" su "${live_user}" -c "
    mkdir -p /home/${live_user}/.config
    kwriteconfig5 --file /home/${live_user}/.config/kscreenlockerrc --group Daemon --key Autolock false
    kwriteconfig5 --file /home/${live_user}/.config/kscreenlockerrc --group Daemon --key LockOnResume false
    grep -qxF 'exec ck-launch-session startplasma-x11' /home/${live_user}/.xinitrc || echo 'exec ck-launch-session startplasma-x11' >> /home/${live_user}/.xinitrc  "
  echo "exec ck-launch-session startplasma-x11" > "${release}/root/.xinitrc"
  echo "exec ck-launch-session startplasma-x11" > "${release}/usr/share/skel/dot.xinitrc"
}

configure_user_groups() {
  # Add the live user to necessary groups for system and hardware access
  chroot "${release}" pw usermod "${live_user}" -G wheel,operator,video
}

configure_devfs() {
  devfs_rules="${release}/etc/devfs.rules"
  rc_conf="${release}/etc/rc.conf"

  # Create a local ruleset for devfs
  echo '[localrules=10]' >> "${devfs_rules}"
  # Add rule to allow users in the 'operator' group to access USB storage devices
  echo "add path 'da*' mode 0666 group operator" >> "${devfs_rules}"

  # Enable this ruleset on boot
  echo 'devfs_system_ruleset="localrules"' >> "${rc_conf}"
}

setup_polkit_rules() {
  polkit_rules_dir="${release}/usr/local/etc/polkit-1/rules.d"
  polkit_rules_file="${polkit_rules_dir}/10-mount.rules"

  # Ensure the directory exists
  mkdir -p "${polkit_rules_dir}"

  # Create the polkit rule file for passwordless mounting
  cat <<EOF > "${polkit_rules_file}"
// Allow udisks2 to mount devices without authentication
// for users in the "wheel" group.
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount") &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
}

# Execute setup routines
patch_etc_files
patch_loader_conf_d
community_setup_liveuser
community_setup_autologin
configure_user_groups
configure_devfs
update_rcconf_dm
lightdm_setup
set_localtime_from_bios
plasma_settings
setup_polkit_rules
setup_xinit
final_setup

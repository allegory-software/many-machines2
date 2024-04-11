machine_prepare() {

checkvars MACHINE MYSQL_ROOT_PASS DHPARAM-

say; say "Disabling cloud-init because it resets our changes on reboot..."
[ -d /etc/cloud ] && touch /etc/cloud/cloud-init.disabled

say; machine_set_hostname $MACHINE
say; machine_set_timezone UTC

# remount /proc so we can pass in secrets via cmdline without them leaking.
say; say "Remounting /proc with option to hide command line args..."
must mount -o remount,rw,nosuid,nodev,noexec,relatime,hidepid=2 /proc
# make that permanent...
must sed -i '/^proc/d' /etc/fstab
append "proc  /proc  proc  defaults,nosuid,nodev,noexec,relatime,hidepid=1  0  0" /etc/fstab

say; apt_get_install sudo htop mc git nginx curl

say; say "Configuring nginx..."
# add dhparam.pem from mm (dhparam is public).
save "$DHPARAM" /etc/nginx/dhparam.pem
# remove nginx placeholder vhost.
must rm -f /etc/nginx/sites-enabled/default
is_running nginx && nginx -s reload

say; say "Configuring git for pushing..."
git_install_git_up
git_config_user "mm@allegory.ro" "Many Machines"

say; say "Configuring kernel to allow binding to ports < 1024 by any user..."
save 'net.ipv4.ip_unprivileged_port_start=0' \
	/etc/sysctl.d/50-unprivileged-ports.conf
must sysctl --system

say; mysql_install
say; tarantool_install
say; acme_install

say; say "Machine prepare done."

}

# midnight commander config

mc_conf_upload() { # MACHINE=
	say "Uploading mc config files to machine '$MACHINE' ..."
	cp_dir ~/.config/mc etc/home/.config/
	SRC_DIR=etc/home/./.config/mc DST_DIR=/root DST_MACHINE=$1 rsync_dir
	ssh_script "mc_conf_spread"
}

mc_conf_spread() {
	local USER
	for USER in `ls -1 /home`; do
		say "Copying mc config files to user '$USER' ..."
		cp_dir /root/.config/mc /home/$USER/.config/ $USER
	done
}

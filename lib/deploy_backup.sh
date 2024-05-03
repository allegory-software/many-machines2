# deploy backup & restore

backup_date() {
	R1=`date -u +%Y-%m-%d-%H-%M-%S`
}

parse_backup_date() {
	local s=${1%.*} # remove extension
	s=${s: -19} # keep date-time part
	local d=${s:0:10} # date part
	local t=${s:11} # time part
	t=${t//-/:}
	R1="$d $t"
}

datetime_to_timestamp() {
	R1=`date -d "$1" +%s`
}

rel_backup_date() { # FILE
	parse_backup_date "$1"; R2=$R1
	datetime_to_timestamp "$R1"
	timeago "$R1"
}

list_deploy_backups() {
	local FMT="%-10s %-20s %s\n"
	printf "$FMT" DEPLOY AGE DATE
	local DEPLOY
	for DEPLOY in `ls backups`; do
		for DATE in `ls -r backups/$DEPLOY`; do
			[[ -L backups/$DEPLOY/$DATE ]] && continue
			rel_backup_date "$DATE"; local AGE=$R1
			printf "$FMT" "$DEPLOY" "$AGE" "$DATE"
		done
	done
}

deploy_db_backup() { # BACKUP_FILE
	local BACKUP_FILE=$1
	checkvars MACHINE DEPLOY BACKUP_FILE
	ssh_script "mysql_backup_db $DEPLOY tmp/$DEPLOY-$DATE-$$.qp"
	SRC_MACHINE=$MACHINE DST_MACHINE= \
		SRC_DIR=/opt/mm/tmp/./$DEPLOY-$DATE-$$.qp \
		DST_DIR=$BACKUP_FILE \
		PROGRESS=1 MOVE=1 rsync_dir
}

deploy_db_restore() { # BACKUP_FILE= DST_MACHINE DST_DB
	checkvars BACKUP_FILE DST_MACHINE DST_DB
	checkfile $BACKUP_FILE
	machine_of "$DST_MACHINE"; local DST_MACHINE=$R1

	SRC_MACHINE= \
		SRC_DIR=$BACKUP_FILE \
		DST_DIR=/opt/mm/tmp/$DST_DB.$$.qp \
		PROGRESS=1 rsync_dir

	MACHINE=$DST_MACHINE ssh_script "
		on_exit must rm tmp/$DST_DB.$$.qp
		mysql_restore_db $DST_DB tmp/$DST_DB.$$.qp
	"
}

deploy_files_backup() { # MACHINE= DEPLOY= BACKUP_DIR [PREV_BACKUP_DIR]
	local BACKUP_DIR=$1 PREV_BACKUP_DIR=$2
	checkvars MACHINE DEPLOY BACKUP_DIR
	md_varfile backup_files; local backup_files_file=$R1
	FILE_LIST_FILE=$backup_files_file \
		SRC_MACHINE=$MACHINE \
		DST_MACHINE= \
		SRC_DIR=/home/$DEPLOY \
		DST_DIR=$BACKUP_DIR \
		LINK_DIR=$PREV_BACKUP_DIR \
		PROGRESS=1 rsync_dir
}

deploy_files_restore() { # DST_MACHINE= DST_DEPLOY= BACKUP_DIR
	local BACKUP_DIR=$1
	checkvars BACKUP_DIR DST_MACHINE DST_DEPLOY
	checkdir $BACKUP_DIR
	machine_of "$DST_MACHINE"; local DST_MACHINE=$R1
	SRC_MACHINE= \
		SRC_DIR=$BACKUP_DIR/./. \
		DST_DIR=/home/$DST_DEPLOY \
		DST_USER=$DST_DEPLOY
		DELETE=1 PROGRESS=1 rsync_dir
}

deploy_backup() {
	checkvars MACHINE DEPLOY
	backup_date; local DATE=$R1
	local DIR=backups/$DEPLOY/$DATE
	must mkdir -p $DIR/files
	deploy_db_backup    $DIR/db.qp
	deploy_files_backup $DIR/files  backups/$DEPLOY/latest/files
	ln_file $DATE backups/$DEPLOY/latest
	R1=$DATE
}

deploy_restore() { # DEPLOY= DATE= DST_MACHINE= [DST_DEPLOY=]
	local DST_DEPLOY=${DST_DEPLOY:-$DEPLOY}
	local DATE=$DATE
	if [[ $DATE == latest ]]; then
		DATE=`readlink backups/$DEPLOY/latest` \
			|| die "No latest backup for deploy '$DEPLOY'"
	fi
	checkvars DEPLOY DATE DST_MACHINE DST_DEPLOY
	machine_of "$DST_MACHINE"; local DST_MACHINE=$R1
	local DIR=backups/$DEPLOY/$DATE
	MACHINE=$DST_MACHINE ssh_script deploy_install
	deploy_db_restore    $DIR/db.qp
	deploy_files_restore $DIR/files
}

# remove old backups according to configured retention policy.
deploy_backups_sweep() {
	mm_var backup_min_age_days     ; local min_age_s=$(( R1 * 3600 * 24 ))
	mm_var backup_min_free_disk_gb ; local min_free_kb=$(( R1 * 1024 * 1024 ))

	local free_kb=`df -l / | awk '(NR > 1) {print $3}'`
	dir_lean_size backups; local used_kb=$(( R1 / 1024 ))
	local must_free=$(( (min_free_kb - free_kb) * 1024 ))
	(( must_free < 0 )) && return 0

	kbytes $must_free
	say "Must free: $R1"

	local d f
	(
	local f
	local now=`date -u +%s`
	for f in `ls backups`; do
		[[ -L backups/$f ]] && continue
		parse_backup_date $f
		datetime_to_timestamp "$R1"
		local d=$R1
		(( d + min_age > now )) && continue
		printf "%s %s\n" $R1 $f
	done
	) | sort -k1n | while read d f; do
		local fsize=`stat -c %s backups/$f`
		DRY=1 rm_file /opt/mm/backups/$f
		must_free=$(( must_free - fsize ))
		(( must_free < 0 )) && break
	done
}

deploy_clone() { # DEPLOY= [LATEST=1] DST_MACHINE= DST_DEPLOY=
	checkvars DEPLOY DST_MACHINE DST_DEPLOY
	[[ $DEPLOY != $DST_DEPLOY ]] || die "DST_DEPLOY == DEPLOY: '$DST_DEPLOY'"
	[[ -d var/deploys/$DST_DEPLOY ]] || die "Deploy already exists: '$DST_DEPLOY'"

	# backup the deploy or use the latest backup.
	local DATE
	if [[ $LATEST ]]; then
		DATE=`readlink backups/$DEPLOY/latest` \
			|| die "No latest backup for deploy '$DEPLOY'"
	else
		deploy_backup
		DATE=$R1
	fi

	# clone the deploy metadata and modify it.
	cp_dir \
		var/deploys/$DEPLOY \
		var/deploys/$DST_DEPLOY
	ln_file ../machines/$DST_MACHINE var/deploys/$DST_DEPLOY/machine

	# install the deploy.
	DEPLOY=$DST_DEPLOY MACHINE=$DST_MACHINE md_install all

	# restore the deploy data over the fresh install.
	deploy_restore
}

md_clone() {
	if [[ $DEPLOY ]]; then
		deploy_clone "$@"
	else
		machine_clone "$@"
	fi
}

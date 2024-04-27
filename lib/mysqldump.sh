# mysqldump backups

mysql_backup_db() { # DB FILE
	local db=$1 file=$2
	checkvars db file
	must mkdir -p $(dirname $file)
	say -n "mysqldump'ing $db to $file ... "

	must mysqldump -u root \
		--no-create-db \
		--extended-insert \
		--order-by-primary \
		--triggers \
		--routines \
		--skip_add_locks \
		--skip-lock-tables \
		--quick \
		$db | qpress -i dump.sql $file

	say "OK. $(stat --printf=%s $file | numfmt --to=iec) written."
}

# rename user in DEFINER clauses in a mysqldump, in order to be able to
# restore the dump into a different db name.
# NOTE: All clauses containing **any user** are renamed!
mysqldump_fix_user() { # USER
	local user=$1
	checkvars user
	sed "s/\`[^\`]*\`@\`localhost\`/\`$user\`@\`localhost\`/g"
}

mysql_restore_db() { # DB FILE
	local db=$1 file=$2
	checkvars db file

	mysql_drop_db   $db
	mysql_create_db $db
	(must qpress -do $file | mysqldump_fix_user $db | must mysql $db) || exit $?

	mysql_create_user   localhost $db localhost $db
	mysql_grant_user_db localhost $db $db
}

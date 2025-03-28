# var files and dirs with include dirs.

varfile() { # DIR VAR
	local DIR="$1"
	local FILE="${2,,}"
	R1=
	[ -f $DIR/$FILE ] && { R1=$DIR/$FILE; return 0; }
	local INC; for INC in `find -L $DIR -maxdepth 10 -name '.?*' | sort`; do
		[ -d $INC ] || continue
		[ -f $INC/$FILE ] && { R1=$INC/$FILE; return 0; }
	done
	return 1
}

cat_varfile() { # DIR VAR [DEFAULT]
	varfile "$1" "$2" || { R1=$3; return 1; }
	catfile $R1 "$3"
}

_add_varfiles() { # DIR
	local FILE
	for FILE in `ls -1Lp $1 | grep -v /`; do # list files & file symlinks only (and no dotfiles)
		local VAR="${FILE^^}"
		if [[ ! -v R2[$VAR] ]]; then
			must catfile $1/$FILE
			R2[$VAR]="$R1"
		fi
	done
}
cat_all_varfiles() { # [LOCAL="local "] DIR
	local DIR=$1
	checkvars DIR
	declare -A R2
	_add_varfiles $DIR
	# NOTE: this dives into the `machine` symlink and includes all machine vars!
	local INC; for INC in `find -L $DIR -maxdepth 10 -name '.?*' | sort`; do
		[ -d $INC ] || continue
		_add_varfiles $INC
	done
	R1=()
	local VAR
	for VAR in "${!R2[@]}"; do
		R1+=("$LOCAL$VAR=\"${R2[$VAR]}\""$'\n')
	done
}

cat_varfiles() { # [LOCAL="local "] DIR [VAR1 ...]
	local DIR=$1; shift
	if [[ $1 ]]; then
		local LINES=()
		local VAR
		for VAR in $@; do
			if cat_varfile "$DIR" "$VAR"; then
				LINES+=("$LOCAL${VAR^^}=\"$R1\""$'\n')
			fi
		done
		R1=("${LINES[@]}")
	else
		cat_all_varfiles "$DIR"
	fi
}

# machine & deploy vars ------------------------------------------------------

md_vardir() { # MACHINE=|DEPLOY=
	if [[ $DEPLOY ]]; then
		checkvars DEPLOY
		R1=var/deploys/$DEPLOY
	else
		checkvars MACHINE
		R1=var/machines/$MACHINE
	fi
}

md_varfile() { # MACHINE=|DEPLOY= VAR
	md_vardir; varfile $R1 "$1"
}

md_vars() { # MACHINE=|DEPLOY= [VAR1 ...]
	md_vardir; cat_varfiles $R1 "$@"
}

md_var() { # MACHINE=|DEPLOY= VAR [DEFAULT]
	local VAR=$1 DEFAULT=$2
	checkvars VAR
	md_vardir; cat_varfile $R1 $VAR "$DEFAULT"
}

mm_var() { cat_varfile var $1; }

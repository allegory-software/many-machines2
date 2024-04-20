# die harder, see https://github.com/capr/die which this extends.

say()       { echo "$@" >&2; }
say_ln()    { printf '=%.0s\n' {1..72}; }
die()       { say -n "ABORT: "; say "$@"; exit 1; }
debug()     { if [[ $DEBUG ]]; then say "$@"; fi; }
run()       { debug -n "EXEC: $@ "; "$@"; local ret=$?; debug "[$ret]"; return $ret; }
must()      { debug -n "MUST: $@ "; "$@"; local ret=$?; debug "[$ret]"; [[ $ret == 0 ]] || die "$@ [$ret]"; }
dry()       { if [[ $DRY ]]; then say "DRY: $@"; else "$@"; fi; }
nag()       { [[ $VERBOSE ]] || return 0; say "$@"; }

# arg checking and sanitizing

checknosp() { # VAL [ERROR...]
	local val="$1"; shift
	[[ "${val}" =~ ( |\') ]] && die "${FUNCNAME[1]}: contains spaces: '$val'"
	[[ "${val}" ]] || die "${FUNCNAME[1]}: $@"
}

checkvars() { # VARNAME1[-] ...
	local var
	for var in $@; do
		if [[ ${var::-1}- == $var ]]; then # spaces allowed
			var=${var::-1}
			[[ ${!var} ]] || die "${FUNCNAME[1]}: $var required"
		else
			[[ ${!var} ]] || die "${FUNCNAME[1]}: $var required"
			[[ ${!var} =~ ( |\') ]] && die "${FUNCNAME[1]}: $var contains spaces"
		fi
	done
	return 0
}

trim() { # VARNAME
	read -rd '' $1 <<<"${!1}"
	return 0
}

# quoting args, vars and bash code for passing scripts through sudo and ssh.

quote_args() { # ARGS...
	# must use an array because we need to quote each arg individually,
	# and not concat and expand them to pass them along, becaue even
	# when quoted they may contain spaces and would expand incorrectly.
	R1=()
	local arg
	local s
	for arg in "$@"; do
		printf -v s "%q" "$arg"
		R1+=("$s")
	done
}

quote_vars() { # VAR1 ...
	R1=()
	local var
	local s
	for var in "$@"; do
		printf -v s "%q=%q\n" "$var" "${!var}"
		R1+=("$s")
	done
}

# enhanced sudo that can:
#  1. inherit a list of vars.
#  2. execute a function from the current script, or an entire script.
#  3. include additional function definitions needed to run said function.
#  4. pass args to said function.
run_as() { # VARS="VAR1 ..." FUNCS="FUNC1 ..." USER "SCRIPT" ARG1 ...
	local user=$1 script=$2; shift 2
	checkvars user script-
	quote_args "$@"; local args="${R1[*]}"
	local vars=$(declare -p DEBUG VERBOSE $VARS 2>/dev/null)
	[[ $FUNCS ]] && local funcs=$(declare -f $FUNCS)
	sudo -u "$user" bash -s <<< "
$vars
$funcs
$script $args
"
}

# reflection

functions_with_prefix() { # PREFIX
	local prefix="$1"
	R1=
	for func_name in $(declare -F | awk '{print $3}'); do
		if [[ $func_name == "$prefix"* ]]; then
			R1+=" ${func_name#$prefix}"
		fi
	done
}

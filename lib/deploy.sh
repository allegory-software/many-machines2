# deploy lib: programs for deployments admin, running as root on a machine administered by mm.

# deploy info ----------------------------------------------------------------

# get it from github: slow.
get_APP_WANT() {
	checkvars REPO APP_VERSION
	local s=$(git ls-remote $REPO refs/heads/$APP_VERSION)
	echo ${s:0:7}
}

# get it locally: fast but wrong.
_get_APP_WANT() {
	must pushd /home/$DEPLOY/app
	run_as $DEPLOY git rev-parse --short $APP_VERSION
	popd
}

get_APP_DEPL() {
	must pushd /home/$DEPLOY/app
	run_as $DEPLOY git rev-parse --short HEAD
	popd
}

get_APP_LATEST() {
	[[ `get_APP_WANT` == `get_APP_DEPL` ]] && echo YES || echo NO!
}

get_SDK_DEPL() {
	must pushd /home/$DEPLOY/app/sdk
	run_as $DEPLOY git rev-parse --short HEAD
	popd
}

get_APP_STATUS() {
	app running && echo RUNNING || echo DOWN!
}

# deploy modules -------------------------------------------------------------

deploy_install_user() {
	[[ -d /home/$DEPLOY ]] && return
	user_create    $DEPLOY
	user_lock_pass $DEPLOY
}

deploy_install_git_keys() {
	git_keys_update $DEPLOY
	git_config_user "mm@allegory.ro" "Many Machines"
}

deploy_preinstall_mysql() {
	checkvars DEPLOY
	mysql_pass_gen_once var/deploys/$DEPLOY/mysql_pass
}

deploy_install_mysql() {
	checkvars DEPLOY MYSQL_PASS-
	mysql_create_db     $DEPLOY
	mysql_create_user   localhost $DEPLOY "$MYSQL_PASS"
	mysql_grant_user_db localhost $DEPLOY $DEPLOY
	mysql_gen_my_cnf    localhost $DEPLOY "$MYSQL_PASS" $DEPLOY
}

deploy_gen_conf() {
	checkvars MACHINE DEPLOY APP MYSQL_PASS SECRET
	local conf=/home/$DEPLOY/$APP/${APP}.conf
	save "\
--deploy vars
deploy = '$DEPLOY'
machine = '$MACHINE'
${ENV:+env = '$ENV'}
${APP_VERSION:+version = '$APP_VERSION'}
db_name = '$DEPLOY'
db_user = '$DEPLOY'
db_pass = '$MYSQL_PASS'
secret = '$SECRET'

--custom vars
${HTTP_PORT:+http_port = $HTTP_PORT}
${HTTP_COMPRESS:+http_compress = $HTTP_COMPRESS}
${SMTP_HOST:+smtp_host = '$SMTP_HOST'}
${SMTP_HOST:+smtp_user = '$SMTP_USER'}
${SMTP_HOST:+smtp_pass = '$SMTP_PASS'}
${DOMAIN:+host = '$DOMAIN'}
${NOREPLY_EMAIL:+noreply_email = '$NOREPLY_EMAIL'}
${DEV_EMAIL:+dev_email = '$DEV_EMAIL'}
${DEFAULT_COUNTRY:+default_country = '$DEFAULT_COUNTRY'}
${SESSION_COOKIE_SECURE_FLAG:+session_cookie_secure_flag = $SESSION_COOKIE_SECURE_FLAG}

log_host = '127.0.0.1'
log_port = 5555
https_addr = false
" $conf $DEPLOY
}

deploy_stop_app() {
	[[ -d /home/$DEPLOY/$APP ]] || return
	(app running && must app stop)
}

deploy_start_app() {
	say; say "Starting the app..."
	must app start
	must app status
}

deploy_install_app() {

	checkvars DEPLOY REPO APP APP_VERSION

	say
	say "Deploying APP=$APP ENV=$ENV VERSION=$APP_VERSION ..."

	say
	git_clone_for $DEPLOY $REPO /home/$DEPLOY/$APP "$APP_VERSION" app

	must ln -sTf $APP /home/$DEPLOY/app

	say
	deploy_gen_conf

	say; say "Installing the app..."
	must app install forealz

}

deploy_install_nginx() {
	[[ $HTTP_PORT && $DOMAIN ]] && {
		local src=/home/$DEPLOY/$APP/www/5xx.html
		local dst=/var/www/$DOMAIN/5xx.html
		if [ -f "$src" ]; then
			cp_file $src $dst
		else
			save "Server down!" $dst
		fi
	}
	[[ $DOMAIN ]] && {
		local ACME; [[ -f /opt/mm/var/.acme.sh.etc/${DOMAIN}_ecc/$DOMAIN.cer ]] || ACME=1
		ACME=$ACME deploy_nginx_config
	}
}

deploy() {
	deploy_install $DEPLOY_MODULES
	say; say "Deploy done."
}

# deploy admin ---------------------------------------------------------------

deploy_secret_gen() {
	must openssl rand 46 | base64 # result is 64 chars
}

deploy_rename() { # OLD_DEPLOY NEW_DEPLOY [nosql]
	local OLD_DEPLOY="$1"
	local NEW_DEPLOY="$2"
	local OPT="$3"
	checkvars OLD_DEPLOY NEW_DEPLOY
	checkvars DEPLOY APP

	local MYSQL_PASS="$(mysql_pass $OLD_DEPLOY)"
	user_rename      $OLD_DEPLOY $NEW_DEPLOY
	mysql_rename_db  $OLD_DEPLOY $NEW_DEPLOY
	[ "$MYSQL_PASS" ] && \
		mysql_gen_my_cnf localhost $NEW_DEPLOY $MYSQL_PASS $NEW_DEPLOY

	deploy_gen_conf
}

deploy_remove() { # DEPLOY DOMAIN=
	local DEPLOY="$1"
	checkvars DEPLOY

	user_remove $DEPLOY

	mysql_drop_db $DEPLOY
	mysql_drop_user localhost $DEPLOY

	[ "$DOMAIN" ] && deploy_nginx_config_remove

	say "Deploy removed."
}

app() {
	checkvars DEPLOY
	must pushd /home/$DEPLOY/app
	VARS="DEBUG VERBOSE" must run_as $DEPLOY ./`readlink ../app` "$@"
	popd
}

test_task() {
	local n=0
	while true; do
		n=$((n+1))
		say "Testing $n (E)"
		echo "Testing $n (O)"
		sleep .5
	done
}

start() {
	if [ -d /home/$1/app ]; then
		DEPLOY=$1 app start
	else
		service_start $1
	fi
}

stop() {
	if [ -d /home/$1/app ]; then
		DEPLOY=$1 app stop
	else
		service_stop $1
	fi
}

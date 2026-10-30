#!/bin/sh
# Set up a project on the VPS: a loopback systemd service, an nginx vhost,
# and a Let's Encrypt certificate.
#
# The project name is the first argument, or the current directory's name.
# A second run fills gaps: a missing certificate, a binary copied up since
# the last run, or a bare ExecStart that does not match the binary's flags.
# An existing vhost, certificate, and LOBBY_KEY are left alone.
#
# This does not install nginx, certbot, or a firewall, and it does not build
# or copy the binary. The binary belongs at /home/dev/<name>/<name>.
# ADDR is always set. If the binary is already in place, its -h output is
# read: a -addr flag is passed on ExecStart, and -open=false is passed when
# that flag defaults to true. A later run repairs a bare ExecStart the same
# way. Copy the binary up and run this again to start the service, or start
# the unit yourself.
set -eu

usage() {
    cat <<'EOF'
Usage: vps.sh [name]

Set up name on the VPS. name defaults to the current directory's basename.
The public host is name.DOMAIN. An existing vhost, certificate, and
LOBBY_KEY are left alone. A unit whose ExecStart is only the binary path
is updated when the binary's -h output asks for -addr.

  DEPLOY_HOST   SSH destination (default: tao). The login must be root.
  DOMAIN        Parent domain (default: pifia.net). Not the full hostname.
  PORT          Loopback port (default: next free port from BASE_PORT).
  BASE_PORT     First port to try when PORT is unset (default: 18080).
  APP_USER      Service account (default: dev). Created if missing.

Examples:
  sh vps.sh
  sh vps.sh asteroids
  DOMAIN=tequionet.org sh vps.sh komikan
  PORT=18090 sh vps.sh
EOF
}

die() {
    printf 'vps: %s\n' "$1" >&2
    exit "${2:-1}"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ $# -gt 1 ]; then
    usage >&2
    exit 2
fi

NAME=${1:-$(basename "$PWD")}
HOST=${DEPLOY_HOST:-tao}
DOMAIN=${DOMAIN:-pifia.net}
PORT=${PORT:-}
BASE_PORT=${BASE_PORT:-18080}
APP_USER=${APP_USER:-dev}

# The name is a DNS label: it becomes the hostname and the unit name.
case $NAME in
"" | *[!A-Za-z0-9-]* | -* | *-)
    die "name must be a hostname label (letters, digits, hyphens; not starting or ending with a hyphen): $NAME" 2
    ;;
esac

if [ "${#NAME}" -gt 63 ]; then
    die "name is longer than 63 characters: $NAME" 2
fi

case $DOMAIN in
*[!A-Za-z0-9.-]* | .* | *. | -* | *- | *..* | *-.* | .*-*)
    die "invalid domain: $DOMAIN" 2
    ;;
*.*) ;;
*)
    die "domain needs a dot: $DOMAIN" 2
    ;;
esac

case $HOST in
"" | *[!A-Za-z0-9._@-]*)
    die "invalid DEPLOY_HOST: $HOST" 2
    ;;
esac

case $APP_USER in
"" | [!A-Za-z]* | *[!A-Za-z0-9_-]*)
    die "invalid APP_USER: $APP_USER" 2
    ;;
esac

check_port() {
    label=$1
    value=$2
    case $value in
    "" | *[!0-9]* | 0*)
        die "invalid $label: $value" 2
        ;;
    esac
    if [ "$value" -gt 65535 ]; then
        die "invalid $label: $value" 2
    fi
}

if [ -n "$PORT" ]; then
    check_port PORT "$PORT"
fi
check_port BASE_PORT "$BASE_PORT"

FQDN=$NAME.$DOMAIN

printf '==> %s on %s\n' "$FQDN" "$HOST"

# The remote half runs on the VPS, as root, under the host's /bin/sh.
ssh -T -o BatchMode=yes -o ConnectTimeout=15 "$HOST" \
    sh -s -- "$NAME" "$FQDN" "${PORT:--}" "$APP_USER" "$BASE_PORT" <<'EOF'
set -eu

NAME=$1
FQDN=$2
PORT=$3
APP_USER=$4
BASE_PORT=$5

if [ "$PORT" = "-" ]; then
    PORT=
fi

die() {
    printf 'vps: %s\n' "$1" >&2
    exit 1
}

say() {
    printf '==> %s\n' "$1"
}

# Extra ExecStart arguments the binary needs. Empty if it is missing, or if
# it listens through ADDR alone. -h is how the Go flag package reports this;
# a binary that ignores -h is stopped by timeout and treated as ADDR-only.
listen_args() {
    probe=$1
    listen_at=$2
    if [ ! -x "$probe" ] || ! command -v timeout >/dev/null 2>&1; then
        return 0
    fi
    help=$(timeout 3 "$probe" -h 2>&1 || true)
    flags=
    if printf '%s\n' "$help" | grep -q '^  -addr '; then
        flags="-addr $listen_at"
    fi
    if printf '%s\n' "$help" | grep -q '^  -open$' \
        && printf '%s\n' "$help" | grep -A1 '^  -open$' | grep -q 'default true'; then
        flags="${flags:+$flags }-open=false"
    fi
    printf '%s\n' "$flags"
}

if [ "$(id -u)" -ne 0 ]; then
    die "ssh login must be root"
fi

for cmd in systemctl nginx certbot useradd ss; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "missing $cmd on the host"
    fi
done

if [ ! -d /etc/nginx/sites-available ] || [ ! -d /etc/nginx/sites-enabled ]; then
    die "nginx is not using sites-available and sites-enabled"
fi

unit=/etc/systemd/system/$NAME.service
dropin_dir=/etc/systemd/system/$NAME.service.d
dropin=$dropin_dir/env.conf
envfile=/etc/$NAME.env
site=/etc/nginx/sites-available/$FQDN
link=/etc/nginx/sites-enabled/$FQDN
cert=/etc/letsencrypt/live/$FQDN/fullchain.pem
home=/home/$APP_USER
dir=$home/$NAME
bin=$dir/$NAME

if ! id "$APP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$APP_USER"
    say "created user $APP_USER"
else
    say "user $APP_USER exists"
    home=$(getent passwd "$APP_USER" | cut -d: -f6)
    if [ -z "$home" ]; then
        die "user $APP_USER has no home directory"
    fi
    dir=$home/$NAME
    bin=$dir/$NAME
fi

if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    chmod 0755 "$dir"
    say "created $dir"
else
    say "directory $dir exists"
fi

unit_port=
if [ -f "$unit" ]; then
    unit_port=$(sed -n 's/.*127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' "$unit" | head -n 1)
    if [ -z "$unit_port" ]; then
        die "$unit has no 127.0.0.1 port"
    fi
fi

used=$(mktemp)
trap 'rm -f "$used"' EXIT
grep -h -oE '127\.0\.0\.1:[0-9]+' /etc/systemd/system/*.service \
    /etc/nginx/sites-available/* 2>/dev/null | sed 's/.*://' >>"$used" || true
ss -tln | awk 'NR > 1 { print $4 }' | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' >>"$used" || true

if [ -n "$PORT" ]; then
    if [ -n "$unit_port" ] && [ "$PORT" != "$unit_port" ]; then
        die "$NAME already listens on $unit_port, not $PORT"
    fi
    if [ "$PORT" != "$unit_port" ] && grep -qx "$PORT" "$used"; then
        die "port $PORT is already in use"
    fi
elif [ -n "$unit_port" ]; then
    PORT=$unit_port
else
    n=$BASE_PORT
    end=$((BASE_PORT + 99))
    PORT=
    while [ "$n" -le "$end" ]; do
        if ! grep -qx "$n" "$used"; then
            PORT=$n
            break
        fi
        n=$((n + 1))
    done
    if [ -z "$PORT" ]; then
        die "no free port from $BASE_PORT to $end"
    fi
fi

addr=127.0.0.1:$PORT

if [ -f "$site" ] && ! grep -q "proxy_pass http://$addr;" "$site"; then
    die "$site does not proxy to $addr"
fi

extra=$(listen_args "$bin" "$addr")
exec_start=$bin
if [ -n "$extra" ]; then
    exec_start="$bin $extra"
fi

if [ ! -f "$unit" ]; then
    first=$(printf '%.1s' "$NAME" | tr '[:lower:]' '[:upper:]')
    rest=$(printf '%s' "$NAME" | cut -c 2-)
    tmp=$(mktemp)
    cat >"$tmp" <<UNIT
# $NAME on the VPS. nginx faces the internet; this process listens on
# loopback only. ADDR is set, and ExecStart passes -addr when the binary
# accepts that flag.

[Unit]
Description=${first}${rest} server
After=network.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$dir
Environment=ADDR=$addr
ExecStart=$exec_start
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
    mv "$tmp" "$unit"
    chmod 0644 "$unit"
    say "wrote $unit ($addr)"

    if [ ! -f "$envfile" ]; then
        key=$(head -c 32 /dev/urandom | base64 | tr -d '=+/')
        old_umask=$(umask)
        umask 077
        printf 'LOBBY_KEY=%s\n' "$key" >"$envfile"
        umask "$old_umask"
        chmod 0600 "$envfile"
        say "wrote $envfile"
    else
        say "$envfile exists, left alone"
    fi

    mkdir -p "$dropin_dir"
    tmp=$(mktemp)
    cat >"$tmp" <<DROP
[Service]
EnvironmentFile=$envfile
DROP
    mv "$tmp" "$dropin"
    chmod 0644 "$dropin"
    say "wrote $dropin"
    systemctl daemon-reload
else
    current=$(sed -n 's/^ExecStart=//p' "$unit" | head -n 1)
    if [ "$current" = "$bin" ] && [ "$exec_start" != "$bin" ]; then
        tmp=$(mktemp)
        sed "s|^ExecStart=.*|ExecStart=$exec_start|" "$unit" >"$tmp"
        mv "$tmp" "$unit"
        chmod 0644 "$unit"
        systemctl daemon-reload
        say "updated ExecStart to $exec_start"
        if systemctl is-enabled --quiet "$NAME"; then
            systemctl restart "$NAME"
            say "restarted $NAME"
        fi
    else
        say "unit $NAME.service exists ($addr), left alone"
    fi
fi

wrote_site=0
if [ ! -f "$site" ]; then
    tmp=$(mktemp)
    cat >"$tmp" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $FQDN;

    location / {
        proxy_pass http://$addr;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }

    location /events {
        proxy_pass http://$addr;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
NGINX
    mv "$tmp" "$site"
    chmod 0644 "$site"
    wrote_site=1
    say "wrote $site"
else
    say "vhost $FQDN exists, left alone"
fi

wrote_link=0
if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    ln -s "$site" "$link"
    wrote_link=1
    say "enabled $FQDN"
fi

if [ "$wrote_site" -eq 1 ] || [ "$wrote_link" -eq 1 ]; then
    if ! nginx -t; then
        if [ "$wrote_link" -eq 1 ]; then
            rm -f "$link"
        fi
        if [ "$wrote_site" -eq 1 ]; then
            rm -f "$site"
        fi
        die "nginx config test failed; new vhost removed"
    fi
    systemctl reload nginx
fi

if [ ! -f "$cert" ]; then
    if ! certbot --nginx --non-interactive --agree-tos --key-type ecdsa \
        --register-unsafely-without-email -d "$FQDN"; then
        die "certificate request failed; $FQDN must point at this host and port 80 must reach nginx"
    fi
    say "issued certificate for $FQDN"
else
    say "certificate for $FQDN exists"
fi

if [ -x "$bin" ]; then
    systemctl enable "$NAME"
    if systemctl is-active --quiet "$NAME"; then
        say "service $NAME is already running"
    else
        systemctl start "$NAME"
        say "started $NAME"
    fi
else
    say "binary $bin is missing; service not started"
    printf '    copy the binary there, then: systemctl enable --now %s\n' "$NAME"
fi

printf 'https://%s\n' "$FQDN"
printf 'loopback %s\n' "$addr"
EOF

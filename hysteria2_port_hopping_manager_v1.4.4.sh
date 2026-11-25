#!/usr/bin/env bash
# Hysteria 2 Port-Hopping Manager v1.4.4
# Ubuntu 22.04/24.04. Dedicated service; does not modify S-UI/Xray.
set -Eeuo pipefail
VERSION="1.4.4"
REPO_RAW_URL="https://raw.githubusercontent.com/Landman-Chio/hysteria2-port-hopping-manager-/main/hysteria2_port_hopping_manager.sh"
DOWNLOAD_TIMEOUT=30
SERVICE="hysteria2-hop"
BASE="/etc/hysteria2-hop"
CONFIG="$BASE/config.yaml"
CLIENT="$BASE/client.yaml"
LINK="$BASE/node-link.txt"
QR="$BASE/node-qr.png"
LINKS="$BASE/links"
QRS="$BASE/qr"
BIN="/usr/local/bin/hysteria"
UNIT="/etc/systemd/system/${SERVICE}.service"
BACKUP="/root/hysteria2-hop-backups"
SCRIPT_SOURCE="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
MANAGER="/usr/local/sbin/hy2-manager"
COMMAND="/usr/local/bin/hy2"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
die(){ echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
ask(){ local v; read -r -p "$1${2:+ [$2]}: " v; printf '%s' "${v:-${2:-}}"; }
need_root(){ [[ $EUID -eq 0 ]] || die "请使用 root 运行：sudo bash $0"; }
yaml_quote(){
  local v="$1"
  [[ "$v" != *$'\n'* && "$v" != *$'\r'* ]] || die "配置值不能包含换行"
  v="${v//\\/\\\\}"; v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}
urlencode(){ jq -rn --arg v "$1" '$v|@uri'; }
check_domain(){
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$ ]] || die "域名格式不正确"
}
check_range(){
  [[ "$1" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]] || die "端口范围格式应为 20000-50000"
  PSTART="${BASH_REMATCH[1]}"; PEND="${BASH_REMATCH[2]}"
  (( PSTART >= 1024 && PEND <= 65535 && PSTART < PEND )) || die "端口范围无效"
  (( PEND - PSTART <= 50000 )) || die "端口跨度过大"
}
backup_old(){
  if [[ -d "$BASE" ]]; then
    mkdir -p "$BACKUP"; chmod 700 "$BACKUP"
    cp -a "$BASE" "$BACKUP/config-$(date +%Y%m%d-%H%M%S)"
    info "旧配置及节点链接已备份到 $BACKUP"
  fi
}
install_shortcut(){
  need_root
  local source_path tmp
  source_path="${BASH_SOURCE[0]:-$SCRIPT_SOURCE}"

  # bash <(curl ...) uses a transient /dev/fd source. Fetch a durable copy.
  if [[ -f "$source_path" && -r "$source_path" && "$source_path" != /dev/fd/* ]]; then
    source_path="$(readlink -f "$source_path" 2>/dev/null || printf '%s' "$source_path")"
    if [[ -e "$MANAGER" && "$source_path" -ef "$MANAGER" ]]; then
      chmod 0755 "$MANAGER"
    else
      install -D -m 0755 "$source_path" "$MANAGER"
    fi
  else
    tmp="$(mktemp)"
    if ! curl -fL --retry 3 --connect-timeout 10 --max-time "$DOWNLOAD_TIMEOUT" "$REPO_RAW_URL" -o "$tmp"; then
      rm -f "$tmp"
      die "当前通过在线管道启动，且无法从 GitHub 下载管理器；请检查网络或手动下载脚本"
    fi
    bash -n "$tmp" || { rm -f "$tmp"; die "GitHub 下载的管理器语法检查失败，拒绝安装"; }
    install -D -m 0755 "$tmp" "$MANAGER"
    rm -f "$tmp"
  fi

  ln -sfn "$MANAGER" "$COMMAND"
  info "管理器已安装：输入 hy2 即可打开菜单"
}
remove_shortcut(){
  rm -f "$COMMAND" "$MANAGER"
}
purge_everything(){
  need_root
  echo
  echo "即将彻底删除本脚本安装的 Hysteria 2 节点及管理工具："
  echo " - 停止并删除 systemd 服务"
  echo " - 删除 Hysteria 核心程序"
  echo " - 删除 /etc/hysteria2-hop（服务端配置、客户端配置、节点链接、二维码、伪装网页）"
  echo " - 删除 hy2 / hy2-manager 管理命令"
  echo " - 尝试删除本脚本添加的对应 UFW UDP 端口规则"
  echo
  warn "不会删除你自己提供的外部 TLS 证书，也无法自动删除云厂商安全组规则。"
  warn "不会卸载 curl、nftables、iptables、qrencode 等可能被其他程序共用的软件包。"
  read -r -p "确认彻底删除？请输入 PURGE-ALL: " confirm
  [[ "$confirm" == "PURGE-ALL" ]] || { info "已取消，未做任何删除"; return; }

  local range=""
  if [[ -f "$CONFIG" ]]; then
    range="$(sed -n 's/^[[:space:]]*listen:[[:space:]]*["'\''"]*:\([0-9][0-9]*-[0-9][0-9]*\)["'\''"]*[[:space:]]*$/\1/p' "$CONFIG" | head -n1 || true)"
  fi

  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "$UNIT"
  systemctl daemon-reload

  # Delete only the matching UDP allow rule, never flush shared firewall tables.
  if [[ -n "$range" ]] && command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw --force delete allow "${range}/udp" >/dev/null 2>&1 || true
  fi

  rm -rf "$BASE"
  rm -f "$BIN"
  remove_shortcut

  echo
  info "本脚本管理的节点、配置、二维码、分享链接和控制面板命令已删除。"
  warn "如曾在云厂商控制台开放 UDP 端口范围，请手动删除对应安全组规则。"
  warn "如使用 ACME 自动证书，或外部证书，请检查证书存储位置；不会擅自删除可能被其他服务共用的证书。"
  warn "系统依赖包及其他服务的防火墙规则均予以保留。"
}
install_deps(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl ca-certificates openssl jq qrencode nftables iptables
}
install_binary(){
  local arch asset tmp
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) asset="hysteria-linux-amd64" ;;
    aarch64|arm64) asset="hysteria-linux-arm64" ;;
    *) die "暂不支持 CPU 架构：$arch" ;;
  esac
  tmp="$(mktemp)"
  curl -fL --retry 3 --connect-timeout 15 \
    "https://github.com/apernet/hysteria/releases/latest/download/${asset}" -o "$tmp"
  install -m 0755 "$tmp" "$BIN"
  rm -f "$tmp"
  "$BIN" version || true
}
write_service(){
  cat > "$UNIT" <<EOF
[Unit]
Description=Hysteria 2 Port Hopping Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN server -c $CONFIG
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$UNIT"
  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null
}
configure_firewall(){
  local start="$1" end="$2" acme="$3"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "${start}:${end}/udp" comment "Hysteria2 port hopping ${SERVICE}" || warn "UFW 添加 UDP 规则失败，请手动放行"
    if [[ "$acme" == "yes" ]]; then
      ufw allow 80/tcp comment "Hysteria2 ACME ${SERVICE}" || warn "UFW 添加 TCP 80 规则失败"
    fi
  else
    warn "未检测到启用中的 UFW。请在云厂商安全组/防火墙放行 UDP ${start}-${end}。"
    [[ "$acme" != "yes" ]] || warn "ACME HTTP-01 还需要公网 TCP 80 入站。"
  fi
}
make_client_artifacts(){
  local domain="$1" port_range="$2" auth="$3" obfs="$4" obfs_pass="$5" label="$6" hop_interval="$7"
  local qauth qobfs qlabel base_port common_query ng_uri vn_uri sr_uri
  command -v qrencode >/dev/null 2>&1 || die "缺少 qrencode，无法生成二维码；请执行 apt-get install -y qrencode"
  command -v jq >/dev/null 2>&1 || die "缺少 jq，无法生成安全编码的节点链接；请执行 apt-get install -y jq"
  mkdir -p "$LINKS" "$QRS"
  qauth="$(urlencode "$auth")"
  qlabel="$(urlencode "$label")"
  base_port="${port_range%%-*}"
  common_query="sni=${domain}&insecure=0"
  if [[ "$obfs" == "yes" ]]; then
    qobfs="$(urlencode "$obfs_pass")"
    common_query="${common_query}&obfs=salamander&obfs-password=${qobfs}"
  fi

  # v2rayNG/v2rayN import mport from URI query.
  ng_uri="hysteria2://${qauth}@${domain}:${base_port}/?mport=${port_range}&${common_query}#${qlabel}"
  vn_uri="$ng_uri"

  # Shadowrocket gets the official Hysteria2 multi-port authority form.
  sr_uri="hysteria2://${qauth}@${domain}:${port_range}/?${common_query}#${qlabel}"

  printf '%s\n' "$ng_uri" > "$LINKS/v2rayng.txt"
  printf '%s\n' "$vn_uri" > "$LINKS/v2rayn.txt"
  printf '%s\n' "$sr_uri" > "$LINKS/shadowrocket.txt"
  chmod 600 "$LINKS/"*.txt
  cp "$LINKS/v2rayng.txt" "$LINK"
  chmod 600 "$LINK"

  {
    printf 'server: "%s:%s"\n' "$domain" "$port_range"
    printf 'auth: "%s"\n' "$auth"
    printf 'tls:\n  sni: "%s"\n  insecure: false\n' "$domain"
    if [[ "$obfs" == "yes" ]]; then
      printf 'obfs:\n  type: salamander\n  salamander:\n    password: "%s"\n' "$obfs_pass"
    fi
    printf 'socks5:\n  listen: 127.0.0.1:1080\n'
    printf 'transport:\n  udp:\n    hopInterval: %ss\n' "$hop_interval"
  } > "$CLIENT"
  chmod 600 "$CLIENT"

  {
    printf 'DOMAIN=%q\\n' "$domain"
    printf 'PORT_RANGE=%q\\n' "$port_range"
    printf 'AUTH=%q\\n' "$auth"
    printf 'OBFS=%q\\n' "$obfs"
    printf 'OBFS_PASS=%q\\n' "$obfs_pass"
    printf 'LABEL=%q\\n' "$label"
    printf 'HOP_INTERVAL=%q\\n' "$hop_interval"
  } > "$BASE/node.env"
  chmod 600 "$BASE/node.env"

  qrencode -o "$QRS/v2rayng.png" -s 8 -m 2 "$ng_uri"
  qrencode -o "$QRS/v2rayn.png" -s 8 -m 2 "$vn_uri"
  qrencode -o "$QRS/shadowrocket.png" -s 8 -m 2 "$sr_uri"
  cp "$QRS/v2rayng.png" "$QR"
  chmod 600 "$QRS/"*.png "$QR"
  [[ -s "$LINKS/v2rayng.txt" && -s "$LINKS/v2rayn.txt" && -s "$LINKS/shadowrocket.txt" ]] || die "节点链接文件生成失败"
  [[ -s "$QRS/v2rayng.png" && -s "$QRS/v2rayn.png" && -s "$QRS/shadowrocket.png" ]] || die "二维码图片生成失败"

  echo
  info "v2rayNG 链接：$LINKS/v2rayng.txt"
  info "v2rayN 链接：$LINKS/v2rayn.txt"
  info "Shadowrocket 链接：$LINKS/shadowrocket.txt"
  info "独立二维码目录：$QRS"
  info "端口跳跃范围：$port_range；客户端间隔：${hop_interval}s"
  echo
  echo "v2rayNG / v2rayN 分享链接："
  cat "$LINKS/v2rayng.txt"
  echo
  echo "Shadowrocket 分享链接："
  cat "$LINKS/shadowrocket.txt"
  echo
  echo "终端二维码（默认显示 v2rayNG/v2rayN 格式）："
  qrencode -t ANSIUTF8 "$ng_uri" || true
}
setup_outbound(){
  # Writes the selected first/default outbound. No ACL is needed for a single default route.
  local mode addr user pass proxy_url
  echo >&2
  echo "选择 Hysteria 服务端出口：" >&2
  echo "1) VPS 本机直连（默认）" >&2
  echo "2) SOCKS5 / SOCKS5H 代理出口（支持 TCP；UDP 取决于代理服务商）" >&2
  echo "3) HTTP / HTTPS 代理出口（仅 TCP；UDP 不支持）" >&2
  mode="$(ask '请选择 [1-3]' '1')"
  case "$mode" in
    1)
      printf 'outbounds:\n  - name: default\n    type: direct\n'
      ;;
    2)
      addr="$(ask 'SOCKS5 地址，格式 host:port')"
      [[ "$addr" =~ ^[A-Za-z0-9.-]+:([0-9]{1,5})$ ]] || die "SOCKS5 地址格式应为 host:port，例如 1.2.3.4:1080"
      local socks_port="${BASH_REMATCH[1]}"
      (( 10#$socks_port >= 1 && 10#$socks_port <= 65535 )) || die "SOCKS5 端口必须为 1-65535"
      user="$(ask 'SOCKS5 用户名（无认证留空）')"
      pass=""
      [[ -z "$user" ]] || pass="$(ask 'SOCKS5 密码')"
      printf 'outbounds:\n  - name: default\n    type: socks5\n    socks5:\n      addr: %s\n' "$(yaml_quote "$addr")"
      if [[ -n "$user" ]]; then
        printf '      username: %s\n      password: %s\n' "$(yaml_quote "$user")" "$(yaml_quote "$pass")"
      fi
      ;;
    3)
      proxy_url="$(ask 'HTTP/HTTPS 代理完整 URL，例如 http://user:pass@host:port')"
      [[ "$proxy_url" =~ ^https?://[^[:space:]]+$ ]] || die "代理 URL 必须以 http:// 或 https:// 开头"
      printf 'outbounds:\n  - name: default\n    type: http\n    http:\n      url: %s\n      insecure: false\n' "$(yaml_quote "$proxy_url")"
      ;;
    *) die "出口类型无效" ;;
  esac
}

install_or_configure(){
  need_root
  install_shortcut
  [[ -r /etc/os-release ]] || die "无法识别系统"
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *debian* ]] || warn "本脚本主要面向 Ubuntu 22.04/24.04。"
  install_deps
  install_binary

  local tls_mode domain email cert key range pstart pend
  local obfs_mode obfs_pass masq_mode masq_url web_dir page_text
  local auth label outbound_file
  echo
  echo "TLS 证书方式："
  echo "1) 使用已有证书（推荐，可复用 acme.sh 证书）"
  echo "2) Hysteria 自动申请 Let's Encrypt（HTTP-01，需要 TCP 80）"
  tls_mode="$(ask '请选择 [1/2]' '1')"
  [[ "$tls_mode" == "1" || "$tls_mode" == "2" ]] || die "TLS 选项无效"
  domain="$(ask '节点域名/SNI，例如 hy2.example.com')"; check_domain "$domain"
  email="" cert="" key=""
  if [[ "$tls_mode" == "1" ]]; then
    cert="$(ask '证书 fullchain.pem 绝对路径')"
    key="$(ask '私钥 privkey.pem 绝对路径')"
    [[ -f "$cert" && -f "$key" ]] || die "证书或私钥文件不存在"
    [[ "$cert" == /* && "$key" == /* ]] || die "证书路径必须是绝对路径"
  else
    email="$(ask 'ACME 联系邮箱')"
    [[ "$email" == *@*.* ]] || die "邮箱格式不正确"
  fi

  range="$(ask 'UDP 端口跳跃范围' '20000-50000')"; check_range "$range"
  pstart="$PSTART"; pend="$PEND"
  local hop_interval
  hop_interval="$(ask '客户端端口跳跃间隔（秒，至少 5）' '30')"
  [[ "$hop_interval" =~ ^[0-9]+$ ]] && (( hop_interval >= 5 && hop_interval <= 3600 )) || die "跳跃间隔必须为 5-3600 秒"

  echo
  echo "Salamander 混淆："
  echo "1) 关闭"
  echo "2) 开启（客户端必须使用相同密码）"
  obfs_mode="$(ask '请选择 [1/2]' '1')"
  [[ "$obfs_mode" == "1" || "$obfs_mode" == "2" ]] || die "混淆选项无效"
  obfs_pass=""
  [[ "$obfs_mode" != "2" ]] || obfs_pass="$(openssl rand -hex 24)"

  echo
  echo "HTTP/3 伪装响应："
  echo "1) 反向代理到 HTTPS 网站"
  echo "2) 本地静态网页"
  echo "3) 自定义文本"
  echo "4) 不配置"
  masq_mode="$(ask '请选择 [1-4]' '1')"
  masq_url=""; web_dir="$BASE/www"; page_text=""
  case "$masq_mode" in
    1)
      masq_url="$(ask '伪装目标 HTTPS URL' 'https://www.example.com/')"
      [[ "$masq_url" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[^[:space:]]*)?$ ]] || die "伪装 URL 格式不正确"
      ;;
    2)
      page_text="$(ask '静态网页标题' 'Welcome')"
      ;;
    3)
      page_text="$(ask '伪装返回文本' 'Welcome')"
      ;;
    4) ;;
    *) die "伪装选项无效" ;;
  esac

  echo
  setup_outbound > /tmp/hy2-outbound-$$.yaml
  outbound_file="/tmp/hy2-outbound-$$.yaml"
  auth="$(openssl rand -hex 24)"
  label="$(ask '节点名称' 'Hysteria2-Hop')"

  backup_old
  mkdir -p "$BASE"; chmod 700 "$BASE"
  if [[ "$masq_mode" == "2" ]]; then
    mkdir -p "$web_dir"
    safe="${page_text//&/&amp;}"; safe="${safe//</&lt;}"; safe="${safe//>/&gt;}"
    printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title></head><body><h1>%s</h1></body></html>\n' "$safe" "$safe" > "$web_dir/index.html"
  fi

  {
    printf 'listen: ":%s-%s"\n' "$pstart" "$pend"
    if [[ "$tls_mode" == "1" ]]; then
      printf 'tls:\n  cert: %s\n  key: %s\n  sniGuard: strict\n' "$(yaml_quote "$cert")" "$(yaml_quote "$key")"
    else
      printf 'acme:\n  domains:\n    - %s\n  email: %s\n' "$(yaml_quote "$domain")" "$(yaml_quote "$email")"
    fi
    printf 'auth:\n  type: password\n  password: %s\n' "$(yaml_quote "$auth")"
    if [[ "$obfs_mode" == "2" ]]; then
      printf 'obfs:\n  type: salamander\n  salamander:\n    password: %s\n' "$(yaml_quote "$obfs_pass")"
    fi
    case "$masq_mode" in
      1) printf 'masquerade:\n  type: proxy\n  proxy:\n    url: %s\n    rewriteHost: true\n' "$(yaml_quote "$masq_url")" ;;
      2) printf 'masquerade:\n  type: file\n  file:\n    dir: %s\n' "$(yaml_quote "$web_dir")" ;;
      3) printf 'masquerade:\n  type: string\n  string:\n    content: %s\n    headers:\n      content-type: "text/plain; charset=utf-8"\n    statusCode: 200\n' "$(yaml_quote "$page_text")" ;;
      4) ;;
    esac
    cat "$outbound_file"
  } > "$CONFIG"
  rm -f "$outbound_file"
  chmod 600 "$CONFIG"

  # Generate client artifacts independently of service startup.
  # This guarantees that the share links and QR images are available for diagnostics
  # even if the daemon later fails to start (e.g. port conflict or certificate issue).
  make_client_artifacts "$domain" "$range" "$auth" "$([[ "$obfs_mode" == "2" ]] && echo yes || echo no)" "$obfs_pass" "$label" "$hop_interval"

  write_service
  configure_firewall "$pstart" "$pend" "$([[ "$tls_mode" == "2" ]] && echo yes || echo no)"
  systemctl restart "$SERVICE"
  sleep 2
  echo
  systemctl --no-pager --full status "$SERVICE" || true
  if ! systemctl is-active --quiet "$SERVICE"; then
    warn "节点链接和二维码已经生成，但服务未正常运行。请查看：journalctl -u ${SERVICE} -n 100 --no-pager"
    warn "修复服务端错误后再连接客户端。"
    exit 1
  fi
  echo
  info "服务端配置：$CONFIG"
  info "客户端 YAML：$CLIENT"
  info "节点链接：$LINK"
  info "二维码 PNG：$QR"
  echo
  warn "节点链接和二维码包含认证凭据，请勿公开发布；文件权限已设为仅 root 可读。"
  warn "SOCKS5 出口是否支持 UDP 取决于上游代理。HTTP/HTTPS 出口不支持 UDP，UDP 请求会失败。"
  warn "Hysteria 分享 URI 支持多端口范围，但跳跃间隔需在客户端配置中设置；分享 URI 不包含客户端本地 hopInterval。"
  warn "请在云厂商安全组放行 UDP ${pstart}-${pend}；使用 ACME HTTP-01 时还需放行 TCP 80。"
}
update_manager(){
  need_root
  local tmp remote_version backup_file
  tmp="$(mktemp)"
  info "正在检查 GitHub 上的管理器版本..."
  if ! curl -fL --retry 3 --connect-timeout 10 --max-time "$DOWNLOAD_TIMEOUT" "$REPO_RAW_URL" -o "$tmp"; then
    rm -f "$tmp"
    die "无法从 GitHub 获取最新脚本，请检查 VPS 网络连接"
  fi
  if ! bash -n "$tmp"; then
    rm -f "$tmp"
    die "远程脚本未通过 bash -n 检查，已取消更新"
  fi
  remote_version="$(sed -n 's/^VERSION="\([0-9][0-9.]*\)"$/\1/p' "$tmp" | head -n1)"
  [[ -n "$remote_version" ]] || { rm -f "$tmp"; die "无法识别远程脚本版本号，已取消更新"; }

  echo "当前运行版本：v$VERSION"
  echo "GitHub 最新版本：v$remote_version"
  if [[ "$remote_version" == "$VERSION" ]]; then
    rm -f "$tmp"
    info "当前已经是 GitHub 上的最新版本。"
    return 0
  fi

  if [[ "$(printf '%s\n%s\n' "$VERSION" "$remote_version" | sort -V | tail -n1)" != "$remote_version" ]]; then
    rm -f "$tmp"
    warn "远程版本低于当前版本，不执行降级。"
    return 0
  fi

  mkdir -p "$(dirname "$MANAGER")"
  if [[ -f "$MANAGER" ]]; then
    backup_file="${MANAGER}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$MANAGER" "$backup_file"
    info "旧管理器已备份：$backup_file"
  fi
  install -m 0755 "$tmp" "$MANAGER"
  rm -f "$tmp"
  ln -sfn "$MANAGER" "$COMMAND"
  info "管理器已更新到 v$remote_version。"
  echo "正在重新启动新版管理器..."
  exec "$MANAGER"
}
certificate_status(){
  need_root
  echo "========== Hysteria 2 证书状态 =========="
  if ! grep -q '^acme:' "$CONFIG"; then
    info "当前配置不是 Hysteria 内置 ACME 模式。"
    return 0
  fi
  local domain acme_dir cert expiry epoch days now found d
  domain="$(awk '/^acme:/{a=1;next} a && /^[^ ]/{a=0} a && /- /{sub(/.*- /,""); gsub(/"/,""); print; exit}' "$CONFIG")"
  acme_dir="$(awk '/^acme:/{a=1;next} a && /^[^ ]/{a=0} a && /dir:/{sub(/.*dir:[ ]*/,""); gsub(/"/,""); print; exit}' "$CONFIG")"
  if [[ -z "$domain" ]]; then warn "无法识别 ACME 域名"; return 1; fi
  if [[ -z "$acme_dir" ]]; then acme_dir="/acme"; fi
  echo "证书域名：$domain"
  echo "ACME 数据目录：$acme_dir"
  if systemctl is-active --quiet "$SERVICE"; then info "Hysteria 服务正在运行"; else warn "服务未运行，自动续期无法由运行中的服务执行"; fi
  found="no"
  for d in "$acme_dir" /acme "$BASE/acme" /root/acme; do
    [[ -d "$d" ]] || continue
    while IFS= read -r -d '' cert; do
      if openssl x509 -in "$cert" -noout -checkhost "$domain" >/dev/null 2>&1; then
        expiry="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2-)"
        epoch="$(date -d "$expiry" +%s 2>/dev/null || true)"
        [[ -n "$epoch" ]] || continue
        now="$(date +%s)"
        days=$(( (epoch-now)/86400 ))
        echo "证书文件：$cert"
        echo "到期时间：$expiry"
        if (( days < 0 )); then warn "证书已过期"
        elif (( days <= 14 )); then warn "证书剩余 $days 天，请检查续期日志"
        else info "证书剩余 $days 天"
        fi
        found="yes"
        break 2
      fi
    done < <(find "$d" -type f -name '*.crt' -print0 2>/dev/null)
  done
  if [[ "$found" != "yes" ]]; then warn "常见 ACME 目录中未找到匹配的 .crt 证书文件；请结合日志检查。"; fi
  echo "最近 ACME 日志："
  journalctl -u "$SERVICE" --since "30 days ago" --no-pager 2>/dev/null | grep -Ei 'acme|certificate|certmagic|renew|obtaining|obtained|challenge|error' | tail -n 60 || true
}
\nupdate_core(){
  need_root; install_deps; install_binary
  if systemctl is-active --quiet "$SERVICE"; then systemctl restart "$SERVICE"; info "核心已更新并重启。"; else info "核心已更新，服务当前未运行。"; fi
}
status(){ systemctl --no-pager --full status "$SERVICE" || true; }
logs(){ journalctl -u "$SERVICE" -n 100 --no-pager || true; }
restart(){ need_root; systemctl restart "$SERVICE"; systemctl --no-pager --full status "$SERVICE" || true; }\nautostart_settings(){
  need_root
  echo "========== 开机自启动设置 =========="
  if systemctl is-enabled --quiet "$SERVICE"; then echo "当前状态：已启用"; else echo "当前状态：未启用"; fi
  echo "1) 启用开机自启动"
  echo "2) 禁用开机自启动（不停止当前服务）"
  echo "3) 查看服务状态"
  echo "0) 返回"
  read -r -p "请选择 [0-3]: " choice
  case "$choice" in
    1) systemctl enable "$SERVICE" && info "已启用开机自启动" ;;
    2) systemctl disable "$SERVICE" && info "已禁用开机自启动；当前服务不会停止" ;;
    3) systemctl is-enabled "$SERVICE" 2>/dev/null || true; systemctl is-active "$SERVICE" 2>/dev/null || true ;;
    0) return 0 ;;
    *) warn "无效选项" ;;
  esac
}

change_outbound(){
  need_root
  [[ -s "$CONFIG" ]] || die "未找到服务端配置：$CONFIG"
  grep -q '^outbounds:[[:space:]]*$' "$CONFIG" || die "当前配置中没有 outbounds 段，拒绝自动修改以免破坏配置"

  local tmp_out tmp_config backup_file
  tmp_out="$(mktemp)"
  tmp_config="$(mktemp)"
  backup_file="$BACKUP/outbound-before-$(date +%Y%m%d-%H%M%S).yaml"
  mkdir -p "$BACKUP"; chmod 700 "$BACKUP"

  echo
  info "仅修改服务端出站代理；域名、证书、认证密码、端口跳跃和客户端链接保持不变。"
  if ! setup_outbound > "$tmp_out"; then
    rm -f "$tmp_out" "$tmp_config"
    die "出站代理输入未完成，原配置未修改"
  fi

  # 本脚本生成的 outbounds 段始终位于配置文件末尾；先备份，再替换该段。
  cp -a "$CONFIG" "$backup_file"
  awk '/^outbounds:[[:space:]]*$/ { exit } { print }' "$CONFIG" > "$tmp_config"
  cat "$tmp_out" >> "$tmp_config"
  chmod 600 "$tmp_config"
  install -m 0600 "$tmp_config" "$CONFIG"
  rm -f "$tmp_out" "$tmp_config"

  if systemctl restart "$SERVICE"; then
    sleep 2
    if systemctl is-active --quiet "$SERVICE"; then
      info "出站代理已更新，服务运行正常。"
      info "原配置备份：$backup_file"
      return 0
    fi
  fi

  warn "新配置启动失败，正在自动恢复修改前的配置。"
  cp -a "$backup_file" "$CONFIG"
  systemctl restart "$SERVICE" || true
  die "出站代理修改失败，已恢复原配置。请查看 journalctl -u $SERVICE -n 100 --no-pager"
}
backup(){
  need_root
  [[ -d "$BASE" ]] || die "未发现配置目录"
  mkdir -p "$BACKUP"; chmod 700 "$BACKUP"
  tar -czf "$BACKUP/backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C /etc "$(basename "$BASE")"
  info "备份完成：$BACKUP"
}
regenerate_artifacts(){
  need_root
  [[ -f "$BASE/node.env" ]] || die "没有保存节点参数。请先选择安装/重新配置节点，或升级后重新部署一次。"
  # node.env is created by this script with shell-escaped values and mode 600.
  # shellcheck disable=SC1090
  source "$BASE/node.env"
  make_client_artifacts "$DOMAIN" "$PORT_RANGE" "$AUTH" "$OBFS" "$OBFS_PASS" "$LABEL" "$HOP_INTERVAL"
  info "三个客户端的链接和二维码已重新生成。"
}
show_link(){
  [[ -f "$LINK" ]] || die "还没有生成节点链接"
  for f in "$LINKS/v2rayng.txt" "$LINKS/v2rayn.txt" "$LINKS/shadowrocket.txt"; do
    if [[ -f "$f" ]]; then
      echo
      echo "===== $(basename "$f") ====="
      cat "$f"
    fi
  done
  echo
  info "二维码目录：$QRS"
}
uninstall(){
  need_root
  read -r -p "输入 DELETE 确认卸载服务和核心（保留配置及节点链接）: " confirm
  [[ "$confirm" == "DELETE" ]] || { info "已取消"; return; }
  mkdir -p "$BACKUP"; chmod 700 "$BACKUP"
  [[ ! -d "$BASE" ]] || cp -a "$BASE" "$BACKUP/before-uninstall-$(date +%Y%m%d-%H%M%S)"
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "$UNIT" "$BIN"
  systemctl daemon-reload
  info "服务和核心已删除；配置备份位于 $BACKUP"
  warn "如需连配置、二维码、节点链接及 hy2 命令一起删除，请使用菜单 9「彻底清理」。"
}
menu(){
  if [[ $EUID -eq 0 ]]; then
    install_shortcut >/dev/null 2>&1 || warn "未能安装 hy2 快捷命令；当前菜单仍可继续使用。"
  fi
  echo "=================================================="
  echo " Hysteria 2 Port-Hopping Manager v${VERSION}"
  echo "=================================================="
  echo "1) 安装 / 重新配置节点"
  echo "2) 更新 Hysteria 核心"
  echo "3) 查看服务状态"
  echo "4) 查看最近日志"
  echo "5) 重启服务"
  echo "6) 备份配置"
  echo "7) 重新生成三个客户端链接和二维码"
  echo "8) 查看节点链接"
  echo "9) 修改 SOCKS5 / HTTP 出站代理（不重建节点）"
  echo "10) 卸载服务和核心（保留配置）"
  echo "11) 彻底清理：删除节点、配置、二维码、链接及 hy2 命令"
  echo "12) 检查并更新管理器（从 GitHub 获取最新版本）"
  echo "13) 查看 TLS / ACME 证书状态"
  echo "14) 开机自启动设置"
  echo "0) 退出"
  read -r -p "请选择 [0-14]: " choice
  case "$choice" in
    1) install_or_configure ;;
    2) update_core ;;
    3) status ;;
    4) logs ;;
    5) restart ;;
    6) backup ;;
    7) regenerate_artifacts ;;
    8) show_link ;;
    9) change_outbound ;;
    10) uninstall ;;
    11) purge_everything ;;
    12) update_manager ;;
    13) certificate_status ;;
    14) autostart_settings ;;
    0) exit 0 ;;
    *) die "无效选项" ;;
  esac
}
menu

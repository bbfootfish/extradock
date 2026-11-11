#!/bin/bash
# ExtraDock 本地稳定代码签名证书初始化（可重复执行）
#
# 目的：用固定的自签代码签名证书替代 ad-hoc 签名。
# ad-hoc 签名的 designated requirement 退化为按 cdhash 精确匹配，
# 每次重新编译二进制变化 -> cdhash 变化 -> TCC 辅助功能授权失效。
# 证书固定后 DR 基于证书，重建不再影响已授予的授权。
#
# 全程不触碰用户开机密码：证书与私钥放在独立的、由本脚本自建的钥匙串里，
# 并以 -A 允许 codesign 无交互访问私钥。

set -u

DIR="$HOME/.extradock-signing"
KC="$HOME/Library/Keychains/ExtraDockSigning.keychain-db"
KC_PASS_FILE="$DIR/keychain.pass"
CERT_CN="ExtraDock Local Signing"

mkdir -p "$DIR"
if [ -f "$KC_PASS_FILE" ]; then
    KC_PASS=$(cat "$KC_PASS_FILE")
else
    KC_PASS="EDLocal$(openssl rand -hex 8)"
    printf '%s' "$KC_PASS" > "$KC_PASS_FILE"
    chmod 600 "$KC_PASS_FILE"
fi

cd "$DIR" || exit 1

# 1) 自签代码签名证书（10 年有效）
if [ ! -f cert.pem ] || ! openssl x509 -in cert.pem -noout -checkend 86400 >/dev/null 2>&1; then
    cat > openssl.cnf <<'CFG'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
C  = CN
O  = bb
OU = BBLOCAL01
CN = ExtraDock Local Signing
[ v3 ]
basicConstraints  = critical,CA:FALSE
keyUsage          = critical,digitalSignature
extendedKeyUsage  = critical,codeSigning
subjectKeyIdentifier = hash
CFG
    openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
        -keyout key.pem -out cert.pem -days 3650 -config openssl.cnf >/dev/null 2>&1 \
        || { echo "ERROR: 证书生成失败"; exit 1; }
    chmod 600 key.pem
    echo "[1/4] 已生成自签代码签名证书（CN=${CERT_CN}，10 年有效）"
else
    echo "[1/4] 复用已有证书"
fi

# macOS Security 框架无法导入 OpenSSL 3 默认的 AES/PBKDF2 封装，
# 必须用传统 3DES + SHA1，否则报 "MAC verification failed (wrong password?)"。
openssl pkcs12 -export -inkey key.pem -in cert.pem -out cert.p12 \
    -passout "pass:$KC_PASS" -name "$CERT_CN" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1 \
    || { echo "ERROR: PKCS#12 生成失败"; exit 1; }
chmod 600 cert.p12

# 2) 独立钥匙串：密码由本脚本设定，codesign 可无交互访问私钥
if [ ! -f "$KC" ]; then
    security create-keychain -p "$KC_PASS" "$KC" >/dev/null 2>&1 \
        || { echo "ERROR: 钥匙串创建失败"; exit 1; }
fi
security unlock-keychain -p "$KC_PASS" "$KC" >/dev/null 2>&1
if ! security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "$CERT_CN"; then
    security import cert.p12 -k "$KC" -P "$KC_PASS" -A \
        -T /usr/bin/codesign -T /usr/bin/xcodebuild >/dev/null 2>&1 \
        || { echo "ERROR: 身份导入失败"; exit 1; }
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null 2>&1 || true
# 加入用户搜索列表，同时保留 login 钥匙串
security list-keychains -d user -s "$KC" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1
echo "[2/4] 独立钥匙串就绪: $KC"

# 3) 用户域信任：仅当身份尚未有效时设置（重复导入会触发 GUI 认证并挂起）
if security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -q "$CERT_CN"; then
    echo "[3/4] 证书已受信任，跳过"
else
    security add-trusted-cert -r trustRoot -p codeSign -k "$KC" \
        -o "$DIR/trust-settings.plist" cert.pem >/dev/null 2>&1 \
        || { echo "ERROR: 信任设置生成失败"; exit 1; }
    security trust-settings-import "$DIR/trust-settings.plist" >/dev/null 2>&1 \
        || { echo "ERROR: 信任设置导入失败"; exit 1; }
    chmod 600 "$DIR/trust-settings.plist"
    echo "[3/4] 已设置代码签名信任（用户域，无需 GUI 认证）"
fi

# 4) 验证：实际签一个临时文件，确认 DR 锚定证书而非 cdhash
echo "[4/4] 钥匙串中可用的代码签名身份："
security find-identity -v -p codesigning "$KC" 2>&1 | sed 's/^/    /'
cp /usr/bin/true /tmp/extradock_signing_probe 2>/dev/null
( codesign --force --sign "$CERT_CN" --timestamp=none /tmp/extradock_signing_probe \
    > /tmp/extradock_signing_probe.log 2>&1; echo "RC=$?" >> /tmp/extradock_signing_probe.log ) &
PROBE_PID=$!
for _ in $(seq 1 20); do
    kill -0 "$PROBE_PID" 2>/dev/null || break
    sleep 0.5
done
if kill -0 "$PROBE_PID" 2>/dev/null; then
    kill -9 "$PROBE_PID" 2>/dev/null || true
    echo "ERROR: 签名自检超时（私钥可能仍需 GUI 授权）"; exit 1
fi
if grep -q "RC=0" /tmp/extradock_signing_probe.log; then
    DR=$(codesign -dr - /tmp/extradock_signing_probe 2>&1 | tail -1)
    echo "    签名自检通过: $DR"
else
    echo "ERROR: 签名自检失败: $(cat /tmp/extradock_signing_probe.log)"; exit 1
fi
echo "SIGNING_IDENTITY=$CERT_CN"
echo "SIGNING_KEYCHAIN=$KC"

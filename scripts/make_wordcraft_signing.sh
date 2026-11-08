#!/usr/bin/env bash
# 为 wordcraft-hmos 生成一份【本地】调试签名（OpenHarmony 本地 CA 链），
# 绑独立 bundle 名 io.github.shaliuxin.wordcraft.hmos，不与用户 photocraft 的
# AGC profile 冲突。产出 signing/ 下的 .cer/.p12/.p7b，供 build-profile.json5 引用。
#
# 注意：这是本地自签 CA 链。HarmonyOS 7.0 真机可能拒绝纯本地签名；若安装被拒，
# 请在 DevEco 里把 bundle 名改为本名、用"自动签名"让 AGC 签发正式调试 profile。
set -euo pipefail

DEVECO="${DEVECO_HOME:-/c/Program Files/Huawei/DevEco Studio}"
JAVA="$DEVECO/jbr/bin/java.exe"
SIGTOOL="$DEVECO/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/signing"
BUNDLE="${WC_BUNDLE:-io.github.shaliuxin.wordcraft.hmos}"
KEYALIAS="wordcraft-debug"
# 口令与设备 UDID 不入库：从环境变量读取（本地调试时自行 export）。
#   export WC_KEYPW=... WC_STOREPW=... WC_UID1=<设备UDID> WC_UID2=<设备UDID>
# 切勿把真实口令/UDID 写回脚本或提交到公开仓库。
KEYPW="${WC_KEYPW:?请 export WC_KEYPW（本地调试 CA 密钥口令，勿入库）}"
STOREPW="${WC_STOREPW:?请 export WC_STOREPW（本地调试 CA 库口令，勿入库）}"
UID1="${WC_UID1:?请 export WC_UID1（设备 UDID，勿入库）}"
UID2="${WC_UID2:?请 export WC_UID2（设备 UDID，勿入库）}"

mkdir -p "$OUT"
cd "$OUT"
echo "bundle=$BUNDLE out=$OUT"
run() { echo "+ $JAVA -jar $SIGTOOL $*"; "$JAVA" -jar "$SIGTOOL" "$@" 2>&1 | grep -iE "success|error|exception" | tail -2 || true; }

# 1) 根 CA 密钥对
rm -f root.jks root-ca.cer app-sub.jks app-sub-ca.cer app.p12 app-cert.cer profile.jks profile-ca.cer profile-cert.cer app-profile.json wordcraft-debug.p7b
run generate-keypair -keyAlias oh-root-ca -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile root.jks -keystorePwd "$STOREPW" -keyPwd "$KEYPW"

# 2) 自签根证书
run generate-ca -keyAlias oh-root-ca -keyAlg ECC -keySize NIST-P-256 -signAlg SHA256withECDSA \
  -subject "C=CN,O=wordcraft,OU=dev,CN=WordCraft Root CA" \
  -keystoreFile root.jks -keystorePwd "$STOREPW" -keyPwd "$KEYPW" \
  -outFile root-ca.cer

# 3) 应用签名子 CA 密钥对（由根 CA 签发）
run generate-keypair -keyAlias oh-app-sub-ca -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile app-sub.jks -keystorePwd "$STOREPW" -keyPwd "$KEYPW"
run generate-ca -keyAlias oh-app-sub-ca -keyAlg ECC -keySize NIST-P-256 -signAlg SHA256withECDSA \
  -issuer "C=CN,O=wordcraft,OU=dev,CN=WordCraft Root CA" \
  -issuerKeyAlias oh-root-ca -issuerKeyPwd "$KEYPW" -issuerKeystorePwd "$STOREPW" -issuerKeystoreFile root.jks \
  -subject "C=CN,O=wordcraft,OU=dev,CN=WordCraft App Signing CA" \
  -keystoreFile app-sub.jks -keystorePwd "$STOREPW" -keyPwd "$KEYPW" \
  -outFile app-sub-ca.cer

# 4) 应用密钥对（p12，供 hvigor storeFile）
run generate-keypair -keyAlias "$KEYALIAS" -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile app.p12 -keystorePwd "$STOREPW" -keyPwd "$KEYPW"

# 5) 应用签名证书（由应用子 CA 签发，含 root+sub 双链）
run generate-app-cert -keyAlias "$KEYALIAS" -keyPwd "$KEYPW" \
  -issuer "C=CN,O=wordcraft,OU=dev,CN=WordCraft App Signing CA" \
  -issuerKeyAlias oh-app-sub-ca -issuerKeyPwd "$KEYPW" -issuerKeystorePwd "$STOREPW" -issuerKeystoreFile app-sub.jks \
  -subject "C=CN,O=wordcraft,OU=dev,CN=wordcraft-hmos" \
  -validity 3650 -signAlg SHA256withECDSA \
  -keystoreFile app.p12 -keystorePwd "$STOREPW" \
  -outForm certChain -rootCaCertFile root-ca.cer -subCaCertFile app-sub-ca.cer \
  -outFile app-cert.cer

# 6) profile 签名子 CA 密钥对
run generate-keypair -keyAlias oh-profile-ca -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile profile.jks -keystorePwd "$STOREPW" -keyPwd "$KEYPW"

# 7) profile 签名 CA 证书（由根 CA 签发）
run generate-ca -keyAlias oh-profile-ca -keyAlg ECC -keySize NIST-P-256 -signAlg SHA256withECDSA \
  -issuer "C=CN,O=wordcraft,OU=dev,CN=WordCraft Root CA" \
  -issuerKeyAlias oh-root-ca -issuerKeyPwd "$KEYPW" -issuerKeystorePwd "$STOREPW" -issuerKeystoreFile root.jks \
  -subject "C=CN,O=wordcraft,OU=dev,CN=WordCraft Profile CA" \
  -keystoreFile profile.jks -keystorePwd "$STOREPW" -keyPwd "$KEYPW" \
  -outFile profile-ca.cer

# 7) provision profile 证书（由 profile CA 签发，含双 CA 链）
run generate-profile-cert -keyAlias oh-profile-ca -keyPwd "$KEYPW" \
  -issuer "C=CN,O=wordcraft,OU=dev,CN=WordCraft Profile CA" \
  -issuerKeyAlias oh-profile-ca -issuerKeyPwd "$KEYPW" -issuerKeystorePwd "$STOREPW" -issuerKeystoreFile profile.jks \
  -subject "C=CN,O=wordcraft,OU=dev,CN=WordCraft Provision Profile Debug" \
  -validity 3650 -signAlg SHA256withECDSA \
  -rootCaCertFile root-ca.cer -subCaCertFile profile-ca.cer \
  -outForm certChain -keystoreFile profile.jks -keystorePwd "$STOREPW" -outFile profile-cert.cer

# 8) 生成 profile json（含 bundle 名 + 设备 UDID）
NB=$(date -u +%s); NA=$((NB + 3*365*24*3600))
APP_B64=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' app-cert.cer | tr -d '\n' | base64 | tr -d '\n')
cat > app-profile.json <<EOF
{
  "version-name": "2.0.0",
  "version-code": 15001,
  "uuid": "6c1a0e2b-4f3d-4b7a-9c2e-wordcraft01",
  "validity": { "not-before": $NB, "not-after": $NA },
  "type": "debug",
  "bundle-info": {
    "developer-id": "55530755",
    "development-certificate": "$APP_B64",
    "bundle-name": "$BUNDLE",
    "apl": "normal",
    "app-feature": "hos_normal_app",
    "app-identifier": "6917620714977119980"
  },
  "baseapp-info": {},
  "permissions": {},
  "debug-info": { "device-ids": ["$UID1", "$UID2"], "device-id-type": "udid" },
  "acls": { "allowed-acls": [] },
  "app-privilege-capabilities": [],
  "issuer": "pki_internal"
}
EOF

# 9) 签 profile -> p7b
run sign-profile -mode localSign -keyAlias oh-profile-ca -keyPwd "$KEYPW" \
  -profileCertFile profile-cert.cer -inFile app-profile.json \
  -signAlg SHA256withECDSA -keystoreFile profile.jks -keystorePwd "$STOREPW" \
  -outFile wordcraft-debug.p7b

echo "=== 产物 ==="
ls -la "$OUT"/*.cer "$OUT"/*.p12 "$OUT"/*.p7b 2>&1 | tr -d '\r'
echo "=== 校验 p7b ==="
"$JAVA" -jar "$SIGTOOL" verify-profile -inFile "$OUT/wordcraft-debug.p7b" 2>&1 | grep -iE "verifiedPassed|message|bundle-name" | head

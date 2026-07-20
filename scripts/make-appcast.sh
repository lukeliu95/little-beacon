#!/bin/zsh
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: make-appcast.sh VERSION BUILD ARCHIVE OUTPUT SIGNATURE_ATTRIBUTES" >&2
  exit 2
fi

VERSION="$1"
BUILD_NUMBER="$2"
ARCHIVE="$3"
OUTPUT="$4"
SIGNATURE_ATTRIBUTES="$5"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$' ]]; then
  echo "invalid semantic version: $VERSION" >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
  echo "invalid numeric build number: $BUILD_NUMBER" >&2
  exit 1
fi
if [[ ! -f "$ARCHIVE" || "$SIGNATURE_ATTRIBUTES" != *'sparkle:edSignature='* ]]; then
  echo "missing archive or Sparkle signature" >&2
  exit 1
fi

ARCHIVE_NAME="${ARCHIVE:t}"
PUB_DATE="$(LC_ALL=C date -R)"
DOWNLOAD_URL="https://github.com/lukeliu95/little-beacon/releases/download/v${VERSION}/${ARCHIVE_NAME}"
RELEASE_URL="https://github.com/lukeliu95/little-beacon/releases/tag/v${VERSION}"

mkdir -p "${OUTPUT:h}"
cat > "$OUTPUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>小灯塔更新</title>
    <link>https://github.com/lukeliu95/little-beacon</link>
    <description>小灯塔 macOS 稳定版更新</description>
    <language>zh-cn</language>
    <item>
      <title>小灯塔 ${VERSION}</title>
      <link>${RELEASE_URL}</link>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure url="${DOWNLOAD_URL}" ${SIGNATURE_ATTRIBUTES} type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

plutil -lint "$OUTPUT" >/dev/null 2>&1 || xmllint --noout "$OUTPUT"
echo "$OUTPUT"

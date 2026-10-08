#!/usr/bin/env bash
# The .deb for Ubuntu and Debian (A-010): AXENT POS installed into a folder of its own, linuxdeploy
# and its Qt plugin gathering beside it the Qt libraries, plugins and QML modules it needs, as for
# the AppImage, and the whole laid out under /opt/axent-pos, with `axent` on the PATH, its menu
# entry and its icon. What it needs of the system, OpenGL, fonts, X11 and the like, it asks for as
# the package's dependencies, read from what the bundled files link to. Removing the package leaves
# a shop's data, which is kept in each user's own folder.
#
#   packaging/deb.sh POS_DIR BUILD_DIR OUT_DIR
#
# POS_DIR is wira-systems/pos at a release's tag, whose menu entry and icon it takes; BUILD_DIR holds
# a Release build of the program alone (cmake --build ... --target ledgry). Kept here, not in pos,
# so any tag can be packaged, those from before this script too. Needs
# qmake of the Qt it was built with on PATH, or QMAKE set to it, and dpkg-deb. Refuses to make a
# package with anything of the Activator's in it: the key tool is never released (A-010).
set -euo pipefail
# A step that fails says which, rather than the script ending in silence.
trap 'echo "deb.sh: stopped at line $LINENO: $BASH_COMMAND" >&2' ERR

source=$(realpath "${1:?the pos checkout}")
build=$(realpath "${2:?its Release build}")
out=$(realpath "${3:-.}")
# The version as CMakeLists.txt has it, or a tag's, v0.1.0-beta.1 as 0.1.0-beta.1.
version=${LEDGRY_VERSION:-}
version=${version#v}
version=${version:-$(sed -n 's/^ *VERSION \([0-9.]*\)$/\1/p' "$source/CMakeLists.txt" | head -1)}
# Debian orders 0.1.0~beta.1 before 0.1.0, as a beta comes before its release.
debversion=${version//-/\~}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# linuxdeploy and its Qt plugin, as AppImages themselves, run without FUSE.
for tool in linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
            linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage; do
    curl -fsSL -o "$work/$(basename "$tool")" "https://github.com/linuxdeploy/$tool"
    chmod +x "$work/$(basename "$tool")"
done
export APPIMAGE_EXTRACT_AND_RUN=1

DESTDIR="$work/AppDir" cmake --install "$build" --prefix /usr > /dev/null

export QMAKE=${QMAKE:-$(command -v qmake6 || command -v qmake)}
# A stand-in of that Qt with no SQL driver but SQLite's: AXENT keeps its shop in SQLite, and the
# others need client libraries a machine may not have, which stops linuxdeploy. The stand-in is
# links to the Qt, never a change to it.
qt=$("$QMAKE" -query QT_INSTALL_PREFIX)
mkdir -p "$work/qt/bin" "$work/qt/plugins"
for part in "$qt"/*; do
    case "$(basename "$part")" in bin|plugins) ;; *) ln -s "$part" "$work/qt/$(basename "$part")" ;; esac
done
for part in "$qt"/bin/*; do ln -s "$part" "$work/qt/bin/$(basename "$part")"; done
rm "$work/qt/bin/qmake"* 2>/dev/null || true
cp "$QMAKE" "$work/qt/bin/qmake"
printf '[Paths]\nPrefix=..\n' > "$work/qt/bin/qt.conf"
for part in "$qt"/plugins/*; do
    [ "$(basename "$part")" = sqldrivers ] || ln -s "$part" "$work/qt/plugins/$(basename "$part")"
done
mkdir -p "$work/qt/plugins/sqldrivers"
ln -s "$qt"/plugins/sqldrivers/libqsqlite.so "$work/qt/plugins/sqldrivers/"
export QMAKE="$work/qt/bin/qmake"
# The Qt libraries of that Qt, before any the machine has of its own (appimage.sh says why).
qtlibs=$("$QMAKE" -query QT_INSTALL_LIBS)
export LD_LIBRARY_PATH="$qtlibs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QML_SOURCES_PATHS="$source/qml"
# Wayland's display plugins beside X11's, so it runs natively on a Wayland desktop, Ubuntu's own.
export EXTRA_PLATFORM_PLUGINS=${EXTRA_PLATFORM_PLUGINS:-"libqwayland-egl.so;libqwayland-generic.so"}
(cd "$work" && ./linuxdeploy-x86_64.AppImage --appdir AppDir --plugin qt \
    --desktop-file AppDir/usr/share/applications/axent.desktop \
    --icon-file AppDir/usr/share/icons/hicolor/256x256/apps/axent.png > linuxdeploy.log 2>&1) || {
    tail -40 "$work/linuxdeploy.log"
    exit 1
}

# The package's files: the program and all it carries in /opt/axent-pos, the menu entry and the
# icon where the desktop finds them, and `axent` on the PATH.
root="$work/root"
mkdir -p "$root/opt/axent-pos" "$root/usr/bin" "$root/usr/share/applications" \
         "$root/usr/share/icons/hicolor/256x256/apps" "$root/DEBIAN"
cp -a "$work/AppDir/usr/." "$root/opt/axent-pos/"
rm -rf "$root/opt/axent-pos/share/applications" "$root/opt/axent-pos/share/icons"

# Wayland's graphics plugin, which linuxdeploy leaves out: without it, on a Wayland desktop the
# program finds no way to draw with OpenGL and closes as it opens. Its libraries are carried already.
mkdir -p "$root/opt/axent-pos/plugins/wayland-graphics-integration-client"
cp "$qt/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so" \
   "$root/opt/axent-pos/plugins/wayland-graphics-integration-client/"

# Only Qt's own libraries are carried. linuxdeploy also copies the system's, GLib's, GnuTLS's,
# systemd's and more, from the Ubuntu it is built on; on a newer one those older copies are loaded
# before the system's and break what the system then loads beside them, the keychain's libsecret
# among them. Each library a system package holds is left to that package, which the package then
# depends on, as the machine's own copy is always the one its other libraries were built with.
for library in "$root"/opt/axent-pos/lib/*.so*; do
    name=$(basename "$library")
    [ -e "$qtlibs/$name" ] && continue
    if dpkg -S "/usr/lib/x86_64-linux-gnu/$name" > /dev/null 2>&1 || dpkg -S "/lib/x86_64-linux-gnu/$name" > /dev/null 2>&1; then
        rm "$library"
    fi
done
ln -s /opt/axent-pos/bin/axent "$root/usr/bin/axent"
cp "$source/packaging/axent.desktop" "$root/usr/share/applications/axent.desktop"
cp "$source/packaging/axent.png" "$root/usr/share/icons/hicolor/256x256/apps/axent.png"

# Nothing of the Activator's: its key tool is never built for a release, and never shipped.
if find "$root" -iname '*ledgry-keys*' -o -iname '*activator*' | grep -q .; then
    echo "deb.sh: refusing to package something of the Activator's:" >&2
    find "$root" -iname '*ledgry-keys*' -o -iname '*activator*' >&2
    exit 1
fi

# What it needs of the system: every library its files link to directly that it does not carry
# itself, found by the package that holds it on this machine. Only those it links to directly:
# what those libraries need in turn is their packages' to name, and a name from the Ubuntu it is
# built on need not exist on a newer one. Read as it runs on a shop's machine, with no
# LD_LIBRARY_PATH of the build's; a library neither carried nor the system's would be missing
# there, so it stops the package.
elves=$(find "$root/opt/axent-pos" -type f \( -name '*.so*' -o -perm -u+x \) -exec file {} + \
    | grep -E 'ELF .*(executable|shared object)' | cut -d: -f1)
depends=""
missing=""
declare -A owners  # each library's package, looked up once
for elf in $elves; do
    needed=$(readelf -d "$elf" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
    found=$(env -u LD_LIBRARY_PATH ldd "$elf" 2>/dev/null || true)
    for soname in $needed; do
        [ -e "$root/opt/axent-pos/lib/$soname" ] && continue
        # ldd prints the loader, ld-linux, as its path alone, with no "=>".
        library=$(awk -v n="$soname" '$1 == n && $3 ~ /^\// { print $3; exit }
            $1 ~ /^\// && $2 ~ /^\(/ && substr($1, length($1) - length(n)) == "/" n { print $1; exit }' <<<"$found")
        case "$library" in
            "") missing+="  $soname, for ${elf#$root}"$'\n'; continue ;;
            "$root"/*) continue ;;
        esac
        if [ -z "${owners[$library]+found}" ]; then
            owners[$library]=$(dpkg -S "$(realpath "$library")" 2>/dev/null || dpkg -S "$library" 2>/dev/null || true)
        fi
        owner=${owners[$library]}
        if [ -n "$owner" ]; then depends+="${owner%%:*}"$'\n'; else missing+="  $library"$'\n'; fi
    done
done
if [ -n "$missing" ]; then
    printf 'deb.sh: these libraries are neither carried nor the system'"'"'s:\n%s' "$(sort -u <<<"$missing")" >&2
    exit 1
fi
depends=$(sort -u <<<"$depends" | sed '/^$/d' | paste -sd, | sed 's/,/, /g')
[ -n "$depends" ] || { echo "deb.sh: found no system libraries it needs, which cannot be" >&2; exit 1; }

size=$(du -sk --exclude=DEBIAN "$root" | cut -f1)
cat > "$root/DEBIAN/control" <<CONTROL
Package: axent-pos
Version: $debversion
Section: misc
Priority: optional
Architecture: amd64
Installed-Size: $size
Depends: $depends
Maintainer: Wira Systems <wira-systems@users.noreply.github.com>
Homepage: https://github.com/wira-systems/releases
Description: AXENT POS, a point of sale for shops, restaurants and salons
 Sell in seconds, keep stock right, and close each day with the cash counted.
 Runs on the shop's own computer, works without the internet, and phones and
 laptops on the shop's Wi-Fi can join it.
CONTROL

deb="$out/axent-pos_${version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$deb" > /dev/null
echo "Made $deb"
echo "Depends: $depends"

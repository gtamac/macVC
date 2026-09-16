#!/bin/bash
# macVC quick builder for macOS (Apple Silicon).
#
# Downloads the prebuilt macVC.app, bakes in the game files from an existing
# install (a previous "Grand Theft Auto Vice City.app", macVC.app, or older
# reVC.app) or your Steam copy of the original GTA Vice City, and drops the
# finished, ready-to-play "Grand Theft Auto Vice City.app" into your Downloads
# folder. Drag it into
# Applications (or just double-click it) to play; macOS enables Game Mode while
# it runs.
#
# On every run it also resets the FPS and MetalFX graphics settings back to
# their defaults, so a value carried over from an older version (where it meant
# something different) can't leave the game in a poor state. Any existing saved
# settings file is edited in place; a fresh install just starts from defaults.
#
# This needs the original Vice City, not the Definitive Edition. The Definitive
# Edition is a different, rebuilt game and will not work.
#
# Nothing here needs administrator privileges, Homebrew, or Xcode.
#
# Usage: quick-install.sh [--dmg] [game_files_dir]
#   --dmg            also wrap the app in a drag-to-Applications
#                    "Grand Theft Auto Vice City.dmg"
#   game_files_dir   optional folder that already holds the game files
#                    (models/gta3.img) — e.g. a copy from a Windows PC — or a
#                    .app that contains them (the Steam "Grand Theft Auto -
#                    Vice City.app", a Wineskin/Wine wrapper like "GTA Vice
#                    City Mac.app", or an installed "Grand Theft Auto Vice
#                    City.app" / macVC.app). If given, it is used instead of an
#                    existing install. With no path, an installed app, the
#                    Steam install, and then ~/Downloads (entries named *Vice*)
#                    are tried in that order.
set -euo pipefail

# The download repository publishes no releases - it has no API token - so the
# assets are committed to it and served straight from the branch.
RELEASE_URL="https://raw.githubusercontent.com/gtamac/macVC/main/macVC-macos-arm64.tar.gz"
SIGNTOOL_URL="https://raw.githubusercontent.com/gtamac/macVC/main/signtool-arm64.tar.gz"
STEAM_SRC="$HOME/Library/Application Support/Steam/steamapps/common/grand theft auto - vice city/Grand Theft Auto - Vice City.app/Contents/Resources/transgaming/c_drive/Program Files/Rockstar Games/Grand Theft Auto Vice City"
DL="$HOME/Downloads"
# The installed app carries the original game's name; macVC stays the name of
# the project, the download repository, and the prebuilt archive.
APP_NAME="Grand Theft Auto Vice City"
VOLNAME="$APP_NAME"

# Per-user settings the game writes on first launch, kept in one shared file
# regardless of where the app lives.
INI="$HOME/Library/Application Support/macVC/macVC.ini"
# Graphics settings forced back to their built-in defaults on every install.
# When a new build changes what a stored value means -- the all-temporal
# MetalFX presets, frame generation -- an old value carried over from a
# previous version can leave the game in a poor state, so these keys always
# start fresh. Format per entry: "Section|Key|Value"; add rows to reset more.
RESET_SETTINGS=(
	"Graphics|MetalFXUpscaling|2"   # Balanced (75%) -- METALFX_DEFAULT_LEVEL
	"Graphics|FrameGeneration|0"    # interpolation off, 30fps engine
)

# ---------------------------------------------------------------------------
# Presentation. Everything degrades to plain "==>" lines when stdout is not a
# terminal (curl | bash ... > log), so nothing below is load-bearing.
# ---------------------------------------------------------------------------
FANCY=no
[ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && FANCY=yes || true

if [ "$FANCY" = yes ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]; then
	# Miami sunset: hot pink fading into ocean cyan.
	G1=$'\033[38;5;213m' G2=$'\033[38;5;207m' G3=$'\033[38;5;171m'
	G4=$'\033[38;5;135m' G5=$'\033[38;5;99m'  G6=$'\033[38;5;81m'
	G7=$'\033[38;5;45m'
	PINK=$'\033[38;5;205m' CYAN=$'\033[38;5;51m'
	GREEN=$'\033[38;5;84m' RED=$'\033[38;5;203m'
	BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
elif [ "$FANCY" = yes ]; then
	G1=$'\033[95m' G2=$'\033[95m' G3=$'\033[35m'
	G4=$'\033[35m' G5=$'\033[36m' G6=$'\033[96m' G7=$'\033[96m'
	PINK=$'\033[95m' CYAN=$'\033[96m'
	GREEN=$'\033[92m' RED=$'\033[91m'
	BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
else
	G1= G2= G3= G4= G5= G6= G7= PINK= CYAN= GREEN= RED= BOLD= DIM= RESET=
fi

SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
BAR_WIDTH=24

banner() {
	printf '\n'
	printf '  %s                               ██╗   ██╗  ██████╗%s\n' "$G1" "$RESET"
	printf '  %s███╗   ███╗  █████╗   ██████╗  ██║   ██║ ██╔════╝%s\n' "$G2" "$RESET"
	printf '  %s████╗ ████║ ██╔══██╗ ██╔════╝  ██║   ██║ ██║%s\n' "$G3" "$RESET"
	printf '  %s██╔████╔██║ ███████║ ██║       ██║   ██║ ██║%s\n' "$G4" "$RESET"
	printf '  %s██║╚██╔╝██║ ██╔══██║ ██║       ╚██╗ ██╔╝ ██║%s\n' "$G5" "$RESET"
	printf '  %s██║ ╚═╝ ██║ ██║  ██║ ╚██████╗   ╚████╔╝  ╚██████╗%s\n' "$G6" "$RESET"
	printf '  %s╚═╝     ╚═╝ ╚═╝  ╚═╝  ╚═════╝    ╚═══╝    ╚═════╝%s\n' "$G7" "$RESET"
	printf '\n'
	printf '  %sGrand Theft Auto: Vice City · Metal · Apple Silicon%s\n' "$DIM" "$RESET"
	printf '\n'
}

STEPS_TOTAL=6
STEP=0
step() {
	STEP=$((STEP + 1))
	printf '\n%s◆%s %s[%d/%d]%s %s\n' "$PINK" "$RESET" "$BOLD" "$STEP" "$STEPS_TOTAL" "$RESET" "$1"
}
ok()   { printf '  %s✔%s %s\n' "$GREEN" "$RESET" "$1"; }
die() { # die <message> [extra lines...]
	printf '  %s✘ error:%s %s\n' "$RED" "$RESET" "$1" >&2
	shift
	local line
	for line in "$@"; do printf '    %s\n' "$line" >&2; done
	exit 1
}

hsize() { # bytes -> human-readable
	awk -v b="${1:-0}" 'BEGIN {
		u[1]="B"; u[2]="KB"; u[3]="MB"; u[4]="GB"; i=1
		while (b >= 1024 && i < 4) { b /= 1024; i++ }
		if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
	}'
}
file_bytes() { stat -f%z "$1" 2>/dev/null || echo 0; }
du_bytes() {
	local kb
	kb=$(du -sk "$1" 2>/dev/null | awk 'NR==1 {print $1}')
	echo $(( ${kb:-0} * 1024 ))
}

draw_bar() { # <glyph+color prefix drawn as-is> <label> <cur bytes> <total bytes>
	local glyph=$1 label=$2 cur=$3 total=$4
	local pct=0 filled=0 bar='' j=0 tdisp='?'
	if [ "$total" -gt 0 ]; then
		pct=$((cur * 100 / total))
		[ "$pct" -gt 100 ] && pct=100
		tdisp=$(hsize "$total")
	fi
	filled=$((pct * BAR_WIDTH / 100))
	while [ "$j" -lt "$BAR_WIDTH" ]; do
		if [ "$j" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
		j=$((j + 1))
	done
	printf '\r  %s %s %s%s%s %3d%%  %s%s / %s%s\033[K' \
		"$glyph" "$label" "$PINK" "$bar" "$RESET" "$pct" \
		"$DIM" "$(hsize "$cur")" "$tdisp" "$RESET"
}

watch_bytes() { # <pid> <label> <total bytes> <getter cmd...> — progress bar until pid exits
	local pid=$1 label=$2 total=$3
	shift 3
	local i=0 rc=0 cur=0
	printf '\033[?25l'
	while kill -0 "$pid" 2>/dev/null; do
		cur=$("$@" 2>/dev/null || echo 0)
		draw_bar "${CYAN}${SPIN[$((i % 10))]}${RESET}" "$label" "$cur" "$total"
		i=$((i + 1))
		sleep 0.2
	done
	wait "$pid" || rc=$?
	printf '\033[?25h'
	if [ "$rc" -eq 0 ]; then
		if [ "$total" -le 0 ]; then
			total=$("$@" 2>/dev/null || echo 0)
		fi
		draw_bar "${GREEN}✔${RESET}" "$label" "$total" "$total"
		printf '\n'
	else
		printf '\r  %s✘%s %s failed\033[K\n' "$RED" "$RESET" "$label"
	fi
	return "$rc"
}

run_task() { # <label> <cmd...> — spinner until the command finishes
	local label=$1
	shift
	if [ "$FANCY" = no ]; then
		echo "==> $label"
		"$@"
		return
	fi
	local i=0 rc=0 pid
	"$@" &
	pid=$!
	printf '\033[?25l'
	while kill -0 "$pid" 2>/dev/null; do
		printf '\r  %s%s%s %s\033[K' "$CYAN" "${SPIN[$((i % 10))]}" "$RESET" "$label"
		i=$((i + 1))
		sleep 0.1
	done
	wait "$pid" || rc=$?
	printf '\033[?25h'
	if [ "$rc" -eq 0 ]; then
		printf '\r  %s✔%s %s\033[K\n' "$GREEN" "$RESET" "$label"
	else
		printf '\r  %s✘%s %s failed\033[K\n' "$RED" "$RESET" "$label"
	fi
	return "$rc"
}

ini_set() { # <file> <section> <key> <value> — set key within [section], preserving everything else
	local file=$1 section=$2 key=$3 value=$4 tmp
	tmp="$(mktemp)" || return 1
	awk -v section="$section" -v key="$key" -v value="$value" '
		function keyline() { print key "=" value; done=1 }
		BEGIN { insec=0; done=0 }
		/^[[:space:]]*\[/ {
			# leaving the target section without the key present: add it here
			if (insec && !done) keyline()
			hdr=$0; sub(/^[[:space:]]*\[/, "", hdr); sub(/\].*$/, "", hdr)
			insec=(hdr == section)
			print; next
		}
		{
			if (insec && !done) {
				k=$0; sub(/[[:space:]]*=.*/, "", k); gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
				if (k == key) { keyline(); next }
			}
			print
		}
		END {
			if (insec && !done) keyline()          # target section was the last one
			else if (!done) { print "[" section "]"; keyline() }  # section absent entirely
		}
	' "$file" > "$tmp" && mv "$tmp" "$file"
}

reset_settings() { # rewrite the RESET_SETTINGS keys to their defaults in the user ini
	# No settings file yet (fresh install, or the game has never run): nothing to
	# reset — the game writes these defaults itself on first launch.
	if [ ! -f "$INI" ]; then
		ok "No saved settings yet — the game starts with default graphics settings"
		return 0
	fi
	local spec section key value
	for spec in "${RESET_SETTINGS[@]}"; do
		section="${spec%%|*}"; spec="${spec#*|}"
		key="${spec%%|*}"; value="${spec#*|}"
		ini_set "$INI" "$section" "$key" "$value" \
			|| { ok "Could not update $key — leaving your settings as they are"; return 0; }
	done
	ok "Reset FPS and MetalFX to their defaults"
}

# ---------------------------------------------------------------------------

WANT_DMG=no
GAME_ARG=""
for arg in "$@"; do
	case "$arg" in
		--dmg) WANT_DMG=yes ;;
		*) GAME_ARG="$arg" ;;
	esac
done

banner

if [ "$(uname -sm)" != "Darwin arm64" ]; then
	die "this installer is for Apple Silicon Macs (arm64) only"
fi

OS_VER="$(sw_vers -productVersion)"
if [ "$(printf '%s\n' "$OS_VER" 26.0 | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" != "26.0" ]; then
	die "macVC requires macOS 26 (Tahoe) or newer (you have $OS_VER)"
fi

TMP=""
DEV=""
cleanup() {
	kill $(jobs -p) 2>/dev/null || true
	[ -n "$DEV" ] && hdiutil detach "$DEV" >/dev/null 2>&1 || true
	[ -n "$TMP" ] && rm -rf "$TMP"
	[ "$FANCY" = yes ] && printf '\033[?25h' || true
}
trap cleanup EXIT

step "Locating the original game files"

# An already-installed app has the game files baked into its GameData folder, so
# upgrades don't need the original install around anymore. macVC.app and
# reVC.app are the names this app shipped under before it took the original
# game's name; people upgrading from them still have their game files in there,
# so look for all three.
EXISTING_SRC=""
for app in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app" "$DL/$APP_NAME.app" \
           "/Applications/macVC.app"     "$HOME/Applications/macVC.app"     "$DL/macVC.app" \
           "/Applications/reVC.app"      "$HOME/Applications/reVC.app"      "$DL/reVC.app"; do
	if [ -f "$app/Contents/Resources/GameData/models/gta3.img" ]; then
		EXISTING_SRC="$app/Contents/Resources/GameData"
		EXISTING_APP="$app"
		break
	fi
done

# Resolve a user-supplied path to the folder that actually holds the game
# files. Accepts the folder itself, or a .app that contains them: the Steam
# "Grand Theft Auto - Vice City.app" (TransGaming layout), a Wineskin/Wine
# wrapper (e.g. "GTA Vice City Mac.app"), or an installed "Grand Theft Auto
# Vice City.app" / macVC.app. The ".app" suffix may be left off the path.
resolve_game_dir() {
	local base="${1%/}" root dir
	local wine_vc="drive_c/Program Files (x86)/Rockstar Games/Grand Theft Auto Vice City"
	for root in "$base" "$base.app"; do
		for dir in \
			"$root" \
			"$root/Contents/Resources/GameData" \
			"$root/Contents/Resources/transgaming/c_drive/Program Files/Rockstar Games/Grand Theft Auto Vice City" \
			"$root/Contents/SharedSupport/prefix/$wine_vc" \
			"$root/$wine_vc"
		do
			if [ -f "$dir/models/gta3.img" ]; then
				echo "$dir"
				return 0
			fi
		done
	done
	return 1
}

# Work out where the original game files come from.
if [ -n "$GAME_ARG" ]; then
	if ! ASSET_SRC="$(resolve_game_dir "$GAME_ARG")"; then
		die "no game files (models/gta3.img) found in $GAME_ARG" \
			"Pass the folder that contains the game files, or a Vice City .app that holds them."
	fi
	ok "Using game files from $ASSET_SRC"
elif [ -n "$EXISTING_SRC" ]; then
	ASSET_SRC="$EXISTING_SRC"
	ok "Using game files from the existing $EXISTING_APP"
elif [ -f "$STEAM_SRC/models/gta3.img" ]; then
	ASSET_SRC="$STEAM_SRC"
	ok "Using game files from the Steam install"
else
	# Last resort: scan the Downloads folder for a Vice City copy — a game
	# folder or any .app layout resolve_game_dir understands (Steam app,
	# Wineskin/Wine wrapper, ...).
	ASSET_SRC=""
	for cand in "$DL"/*; do
		[ -d "$cand" ] || continue
		case "$(basename "$cand" | tr '[:upper:]' '[:lower:]')" in
			*vice*) ;;
			*) continue ;;
		esac
		if ASSET_SRC="$(resolve_game_dir "$cand")"; then
			break
		fi
		ASSET_SRC=""
	done
	if [ -n "$ASSET_SRC" ]; then
		ok "Using game files from $ASSET_SRC"
	else
		die "GTA Vice City game files not found" \
			"macVC needs the original Vice City, not the Definitive Edition." \
			"Install it through Steam first (https://store.steampowered.com/app/12110/)," \
			"drop a copy (folder or .app) into ~/Downloads with \"Vice\" in its name," \
			"or pass a folder (or Vice City .app, e.g. a Wineskin wrapper) that" \
			"already contains the game files:" \
			"  $0 /path/to/ViceCity"
	fi
fi

TMP="$(mktemp -d)"
APP="$TMP/$APP_NAME.app"
GDATA="$APP/Contents/Resources/GameData"

step "Downloading macVC"
if [ "$FANCY" = yes ]; then
	DL_TOTAL="$(curl -sIL "$RELEASE_URL" 2>/dev/null \
		| awk 'tolower($1)=="content-length:" {cl=$2} END {printf "%d", cl}' || echo 0)"
	case "$DL_TOTAL" in ''|*[!0-9]*) DL_TOTAL=0 ;; esac
	curl -fsSL -o "$TMP/macVC.tar.gz" "$RELEASE_URL" &
	watch_bytes $! "macVC-macos-arm64.tar.gz" "$DL_TOTAL" file_bytes "$TMP/macVC.tar.gz" \
		|| die "download failed — check your connection and try again"
else
	echo "==> Downloading macVC..."
	curl -fL --progress-bar -o "$TMP/macVC.tar.gz" "$RELEASE_URL"
fi
run_task "Unpacking macVC.app" tar -xzf "$TMP/macVC.tar.gz" -C "$TMP"

# The archive ships the bundle as macVC.app with macVC display names; the
# installed copy takes the original game's name — in the folder name and in
# what the menu bar and Dock show.
mv "$TMP/macVC.app" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" \
	-c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"

step "Baking the game files into the app"
# macVC uses Contents/Resources/GameData as its working directory. The prebuilt
# app ships macVC's own game files there. Set them aside, copy the originals in,
# then restore macVC's files on top so they win. (Plain cp -R: BSD cp -n exits
# non-zero when it skips a file, tripping `set -e`.)
bake_files() {
	cp -R "$GDATA" "$TMP/seed"
	cp -R "$ASSET_SRC/." "$GDATA/"
	cp -R "$TMP/seed/." "$GDATA/"
}
if [ "$FANCY" = yes ]; then
	BAKE_TOTAL=$(( $(du_bytes "$GDATA") + $(du_bytes "$ASSET_SRC") ))
	bake_files &
	watch_bytes $! "Copying game data" "$BAKE_TOTAL" du_bytes "$GDATA" \
		|| die "copying the game files failed"
else
	echo "==> Baking the game files into the app (about 1.5 GB)..."
	bake_files
fi

# Stamp the bundle with the checksum of the downloaded binary, taken before
# the re-sign below rewrites it. The game compares this stamp against the
# release's version.sha at startup and offers to re-run this installer when
# they differ.
shasum -a 256 "$APP/Contents/MacOS/macVC" | awk '{print $1}' > "$APP/Contents/Resources/version.sha"

step "Signing the app"
# Baking the game files in invalidates the bundle's signature, and an arm64
# app has to carry a valid one to launch at all. codesign could do this, but
# signing the bundled dylibs pulls in the Xcode Command Line Tools, which this
# installer must not require — so the release ships a small self-contained
# signer instead. See AGENTS.md, "Bundled signing tool".
#
# -Cadhoc is required: plain `ldid -S` writes a CodeDirectory with no adhoc
# flag, which macOS treats as unsigned. Nested code first, then the
# executable, the order codesign --deep uses. -I keeps the bundle identifier,
# which ldid would otherwise set to the file name.
# Explicit `|| return` on every step: the caller invokes this behind `||`,
# which makes bash ignore `set -e` for the whole function body.
sign_bundle() {
	xattr -cr "$APP" 2>/dev/null || true
	curl -fsSL -o "$TMP/signtool.tar.gz" "$SIGNTOOL_URL" || return 1
	tar -xzf "$TMP/signtool.tar.gz" -C "$TMP" || return 1
	xattr -cr "$TMP/signtool" 2>/dev/null || true
	local LDID="$TMP/signtool/ldid" BUNDLE_ID lib
	BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
		"$APP/Contents/Info.plist" 2>/dev/null || echo "com.github.gtamac.macVC")"
	for lib in "$APP"/Contents/Frameworks/*.dylib; do
		[ -e "$lib" ] || continue
		"$LDID" -Cadhoc -S "$lib" || return 1
	done
	"$LDID" -Cadhoc -I"$BUNDLE_ID" -S "$APP/Contents/MacOS/macVC"
}
run_task "Ad-hoc signing the app bundle" sign_bundle || die "signing failed"

step "Resetting graphics settings"
reset_settings

mkdir -p "$DL"

outro() {
	printf '\n'
	printf '%s✔ Done!%s %s\n' "$GREEN$BOLD" "$RESET" "$1"
	printf '  %s\n' "$2"
	printf '  macOS enables Game Mode while it runs.\n'
	printf '\n'
	printf '       %s🌴  Welcome to Vice City  🌴%s\n' "$PINK" "$RESET"
	printf '       %sfinished in %dm %02ds%s\n' "$DIM" $((SECONDS / 60)) $((SECONDS % 60)) "$RESET"
	printf '\n'
}

if [ "$WANT_DMG" = no ]; then
	step "Installing"
	rm -rf "$DL/$APP_NAME.app"
	mv "$APP" "$DL/$APP_NAME.app"
	ok "Placed $APP_NAME.app in $DL"
	outro "$DL/$APP_NAME.app is ready." \
		"Drag it into your Applications folder (or just double-click it) to play."
	open -R "$DL/$APP_NAME.app"
	exit 0
fi

step "Building the disk image"
# Stage the app plus an Applications shortcut, then let hdiutil size the image
# from the actual files (thousands of small audio files add a lot of overhead,
# so a fixed margin is unreliable).
STAGE="$TMP/stage"
mkdir -p "$STAGE"
mv "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
TMPDMG="$TMP/rw.dmg"
dmg_create() { hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW "$TMPDMG" >/dev/null; }
run_task "Creating the disk image" dmg_create || die "hdiutil create failed"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$TMPDMG" | grep -E '^/dev/' | awk 'NR==1{print $1}')

# Lay out the drag-to-Applications window (best effort; needs an interactive Finder).
osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 900, 430}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set position of item "$APP_NAME.app" of container window to {130, 165}
    set position of item "Applications" of container window to {370, 165}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEV" >/dev/null; DEV=""
rm -f "$DL/$APP_NAME.dmg"
dmg_convert() { hdiutil convert "$TMPDMG" -format UDZO -imagekey zlib-level=9 -o "$DL/$APP_NAME.dmg" >/dev/null; }
run_task "Compressing the disk image" dmg_convert || die "hdiutil convert failed"
ok "Created $DL/$APP_NAME.dmg"

outro "$DL/$APP_NAME.dmg is ready." \
	"Opening it now — drag the app into the Applications folder to install."
open "$DL/$APP_NAME.dmg"

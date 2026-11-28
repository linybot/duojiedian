Name:       linybot
Version:    1.7.1
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://linybot.top
Vendor:     linybot <info@linybot.top>
Requires:   gtk3 libxcb libXfixes alsa-lib libva gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo libdrm.so.2()(64bit) libEGL.so.1()(64bit) libGLESv2.so.2()(64bit)
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)
# libdrmtap is dlopen-ed by the root service only when DRM capture is on, and falls back if it cannot
# load, so its own dependencies (newer glibc, EGL, libdrm) must not become requirements of the package.
%global __requires_exclude_from ^/usr/lib/linybot/.*$
%global __provides_exclude_from ^/usr/lib/linybot/.*$

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/linybot" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/linybot"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/linybot.service -t "%{buildroot}/usr/share/linybot/files"
install -Dm 644 $HBB/res/linybot.desktop -t "%{buildroot}/usr/share/linybot/files"
install -Dm 644 $HBB/res/linybot-link.desktop -t "%{buildroot}/usr/share/linybot/files"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/linybot.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/linybot.svg"
mkdir -p "%{buildroot}/usr/lib/linybot"
so=$(find "${DRMTAP_PREBUILT_DIR:-${HBB}/third_party/libdrmtap/build-pkg}" -maxdepth 1 -type f -name 'libdrmtap.so.0.*' 2>/dev/null || true)
if [ -n "$so" ]; then install -Dm 755 "$so" -t "%{buildroot}/usr/lib/linybot"; ln -s "$(basename "$so")" "%{buildroot}/usr/lib/linybot/libdrmtap.so.0"; fi

%files
/usr/share/linybot/*
/usr/lib/linybot
/usr/share/linybot/files/linybot.service
/usr/share/icons/hicolor/256x256/apps/linybot.png
/usr/share/icons/hicolor/scalable/apps/linybot.svg
/usr/share/linybot/files/linybot.desktop
/usr/share/linybot/files/linybot-link.desktop

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop linybot || true
  ;;
esac

%post
cp /usr/share/linybot/files/linybot.service /etc/systemd/system/linybot.service
cp /usr/share/linybot/files/linybot.desktop /usr/share/applications/
cp /usr/share/linybot/files/linybot-link.desktop /usr/share/applications/
ln -sf /usr/share/linybot/linybot /usr/bin/linybot
systemctl daemon-reload
systemctl enable linybot
systemctl start linybot
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop linybot || true
    systemctl disable linybot || true
    rm /etc/systemd/system/linybot.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/bin/linybot || true
    rmdir /usr/lib/linybot || true
    rmdir /usr/local/linybot || true
    rmdir /usr/share/linybot || true
    rm /usr/share/applications/linybot.desktop || true
    rm /usr/share/applications/linybot-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
    rmdir /usr/lib/linybot || true
    rmdir /usr/local/linybot || true
  ;;
esac

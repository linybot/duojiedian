Name:       linybot
Version:    1.7.7
Release:    0
Summary:    RPM package
License:    GPL-3.0
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/linybot/
mkdir -p %{buildroot}/usr/share/linybot/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/linybot %{buildroot}/usr/bin/linybot
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/linybot/libsciter-gtk.so
install $HBB/res/linybot.service %{buildroot}/usr/share/linybot/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/linybot.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/linybot.svg
install $HBB/res/linybot.desktop %{buildroot}/usr/share/linybot/files/
install $HBB/res/linybot-link.desktop %{buildroot}/usr/share/linybot/files/

%files
/usr/bin/linybot
/usr/share/linybot/libsciter-gtk.so
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
    rm /usr/share/applications/linybot.desktop || true
    rm /usr/share/applications/linybot-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac

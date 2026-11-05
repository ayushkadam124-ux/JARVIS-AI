#!/data/data/com.termux/files/usr/bin/bash
# YESMIN AI: Termux se APK build karne ki script
set -e
cd ~/yesmin-ai

pkg update -y
pkg install -y openjdk-17 gradle aapt2 wget unzip

export ANDROID_HOME=$HOME/android-sdk
if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
  mkdir -p $ANDROID_HOME/cmdline-tools
  wget -O /tmp/cmdtools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  unzip -q /tmp/cmdtools.zip -d $ANDROID_HOME/cmdline-tools
  mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest
fi
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin

yes | sdkmanager --licenses >/dev/null || true
sdkmanager "platforms;android-35" "build-tools;34.0.0"

echo "sdk.dir=$ANDROID_HOME" > local.properties
# Termux ARM par Google ka aapt2 nahi chalta, isliye Termux wala use karo
grep -q aapt2FromMavenOverride gradle.properties || \
  echo "android.aapt2FromMavenOverride=$PREFIX/bin/aapt2" >> gradle.properties

gradle assembleDebug --no-daemon

APK=app/build/outputs/apk/debug/app-debug.apk
cp "$APK" ~/storage/downloads/yesmin-ai.apk 2>/dev/null || true
echo "Ban gaya: $APK (aur Downloads/yesmin-ai.apk)"

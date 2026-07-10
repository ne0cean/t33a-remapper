.class public Lcom/ateam/wadbkeeper/BootReceiver;
.super Landroid/content/BroadcastReceiver;
.source "BootReceiver.java"

# BOOT_COMPLETED 수신 → Settings.Global adb_wifi_enabled=1
# (무선 디버깅은 재부팅마다 OS가 끔 — 이 앱이 부팅 직후 되켬)

.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V
    return-void
.end method

.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .locals 4
    invoke-virtual {p1}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;
    move-result-object v0
    const-string v1, "adb_wifi_enabled"
    const/4 v2, 0x1
    invoke-static {v0, v1, v2}, Landroid/provider/Settings$Global;->putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
    move-result v2
    const-string v3, "WADBKeeper"
    if-eqz v2, :cond_fail
    const-string v0, "boot: adb_wifi_enabled=1 set OK"
    invoke-static {v3, v0}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    return-void
    :cond_fail
    const-string v0, "boot: putInt FAILED (WRITE_SECURE_SETTINGS not granted?)"
    invoke-static {v3, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I
    return-void
.end method

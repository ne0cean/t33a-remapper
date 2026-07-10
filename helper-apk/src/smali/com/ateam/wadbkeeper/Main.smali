.class public Lcom/ateam/wadbkeeper/Main;
.super Landroid/app/Activity;
.source "Main.java"

# 런처 아이콘 탭 = 수동 재활성화 + 설치 직후 stopped state 해제용

.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Landroid/app/Activity;-><init>()V
    return-void
.end method

.method protected onCreate(Landroid/os/Bundle;)V
    .locals 4
    invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
    invoke-virtual {p0}, Landroid/app/Activity;->getContentResolver()Landroid/content/ContentResolver;
    move-result-object v0
    const-string v1, "adb_wifi_enabled"
    const/4 v2, 0x1
    invoke-static {v0, v1, v2}, Landroid/provider/Settings$Global;->putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
    move-result v2
    const-string v3, "WADBKeeper"
    if-eqz v2, :cond_fail
    const-string v0, "main: adb_wifi_enabled=1 set OK"
    invoke-static {v3, v0}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    goto :goto_done
    :cond_fail
    const-string v0, "main: putInt FAILED (WRITE_SECURE_SETTINGS not granted?)"
    invoke-static {v3, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I
    :goto_done
    invoke-virtual {p0}, Landroid/app/Activity;->finish()V
    return-void
.end method

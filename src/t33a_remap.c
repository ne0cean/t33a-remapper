#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <time.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sched.h>
#include <linux/input.h>
#include <linux/uinput.h>

#define DEVICE_NAME "T33A"
#define PID_FILE    "/data/local/tmp/t33a.pid"
#define STATUS_FILE "/data/local/tmp/t33a.status"
#define LOG_FILE    "/sdcard/Download/t33a.log"
#define HEARTBEAT_FILE "/data/local/tmp/t33a.heartbeat"
#define RESTART_DELAY 1
#define CONFIG_FILE "/data/local/tmp/t33a.conf"
#define LOG_MAX_LINES 200
#define HEARTBEAT_SEC 60

static volatile int running = 1;
static volatile pid_t child_pid = 0;

typedef struct {
    int from;
    int to;
    int double_click;  /* 1 = emit key twice on single press */
    int wakeup;        /* 1 = emit KEY_WAKEUP first (for power-key source) */
    int tap;           /* 1 = inject screen tap instead of key */
    int tap_x;
    int tap_y;
} mapping_t;

static mapping_t mappings[64];
static int mapping_count = 0;

static void cleanup(int sig) { (void)sig; running = 0; }

static void supervisor_cleanup(int sig) {
    running = 0;
    if (child_pid > 0) kill(child_pid, SIGTERM);
}

/* Write machine-readable status file for watchdog/notification */
static void write_status(const char *state) {
    FILE *f = fopen(STATUS_FILE, "w");
    if (f) { fprintf(f, "%s\n", state); fclose(f); }
}

/* Append human-readable log entry */
static void log_event(const char *msg) {
    FILE *f = fopen(LOG_FILE, "a");
    if (!f) return;
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    fprintf(f, "%04d-%02d-%02d %02d:%02d:%02d %s\n",
            t->tm_year+1900, t->tm_mon+1, t->tm_mday,
            t->tm_hour, t->tm_min, t->tm_sec, msg);
    fclose(f);
}

/* Touch heartbeat file — last alive timestamp.
 * Watched by relay; missing heartbeat for >2*HEARTBEAT_SEC = daemon hung. */
static void heartbeat(const char *state) {
    FILE *f = fopen(HEARTBEAT_FILE, "w");
    if (!f) return;
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    fprintf(f, "%04d-%02d-%02d %02d:%02d:%02d %s\n",
            t->tm_year+1900, t->tm_mon+1, t->tm_mday,
            t->tm_hour, t->tm_min, t->tm_sec, state);
    fclose(f);
}

static void load_config(void) {
    mapping_count = 0;
    FILE *f = fopen(CONFIG_FILE, "r");
    if (!f) {
        /* Default fallback mappings */
        mappings[mapping_count++] = (mapping_t){KEY_HOMEPAGE, KEY_1, 1, 0};
        mappings[mapping_count++] = (mapping_t){KEY_ENTER,    KEY_0, 0, 0};
        mappings[mapping_count++] = (mapping_t){KEY_POWER,    KEY_H, 0, 1};
        log_event("config not found — using defaults");
        return;
    }

    char line[128];
    while (fgets(line, sizeof(line), f) && mapping_count < 64) {
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') continue;
        int from, tap_x, tap_y;
        /* tap mapping: "116 tap 1047 483" */
        if (sscanf(line, "%d tap %d %d", &from, &tap_x, &tap_y) == 3) {
            mappings[mapping_count].from        = from;
            mappings[mapping_count].to          = 0;
            mappings[mapping_count].double_click = 0;
            mappings[mapping_count].wakeup      = 0;
            mappings[mapping_count].tap         = 1;
            mappings[mapping_count].tap_x       = tap_x;
            mappings[mapping_count].tap_y       = tap_y;
            mapping_count++;
            continue;
        }
        int from2, to;
        if (sscanf(line, "%d %d", &from2, &to) == 2) {
            mappings[mapping_count].from         = from2;
            mappings[mapping_count].to           = to;
            mappings[mapping_count].double_click = (strstr(line, "dbl")    != NULL) ? 1 : 0;
            mappings[mapping_count].wakeup       = (strstr(line, "wakeup") != NULL) ? 1 : 0;
            mappings[mapping_count].tap          = 0;
            mapping_count++;
        }
    }
    fclose(f);
    char msg[64];
    snprintf(msg, sizeof(msg), "loaded %d mappings from config", mapping_count);
    log_event(msg);
}

static int remap_key(int code) {
    for (int i = 0; i < mapping_count; i++) {
        if (code == mappings[i].from) return mappings[i].to;
    }
    return code;
}

static int is_double_click(int orig_code) {
    for (int i = 0; i < mapping_count; i++) {
        if (orig_code == mappings[i].from) return mappings[i].double_click;
    }
    return 0;
}

static int is_wakeup(int orig_code) {
    for (int i = 0; i < mapping_count; i++) {
        if (orig_code == mappings[i].from) return mappings[i].wakeup;
    }
    return 0;
}

static mapping_t *find_tap(int orig_code) {
    for (int i = 0; i < mapping_count; i++) {
        if (orig_code == mappings[i].from && mappings[i].tap) return &mappings[i];
    }
    return NULL;
}

static void emit_tap(int tap_x, int tap_y) {
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "input tap %d %d &", tap_x, tap_y);
    system(cmd);
}

static void emit_event(int fd, __u16 type, __u16 code, __s32 value) {
    struct input_event ev = {0};
    ev.type = type;
    ev.code = code;
    ev.value = value;
    write(fd, &ev, sizeof(ev));
}

static void emit_double_click(int uifd, int key_code) {
    /* First click: press + release */
    emit_event(uifd, EV_KEY, key_code, 1);
    emit_event(uifd, EV_SYN, SYN_REPORT, 0);
    emit_event(uifd, EV_KEY, key_code, 0);
    emit_event(uifd, EV_SYN, SYN_REPORT, 0);
    /* Short gap between clicks */
    usleep(100000); /* 100ms — 8ms was too short, Android drops both events */
    /* Second click: press + release */
    emit_event(uifd, EV_KEY, key_code, 1);
    emit_event(uifd, EV_SYN, SYN_REPORT, 0);
    emit_event(uifd, EV_KEY, key_code, 0);
    emit_event(uifd, EV_SYN, SYN_REPORT, 0);
}

static int find_device(void) {
    char path[64], name[256];
    int fd;
    for (int i = 0; i < 20; i++) {
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        fd = open(path, O_RDONLY);
        if (fd < 0) continue;
        if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0 &&
            strcmp(name, DEVICE_NAME) == 0)
            return fd;
        close(fd);
    }
    return -1;
}

static int create_uinput(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) return -1;

    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_EVBIT, EV_SYN);
    ioctl(fd, UI_SET_EVBIT, EV_MSC);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);

    /* Register only alpha/num/common keys — avoid DPAD/GAMEPAD range */
    for (int i = KEY_1; i <= KEY_0; i++)
        ioctl(fd, UI_SET_KEYBIT, i);
    for (int i = KEY_Q; i <= KEY_P; i++)
        ioctl(fd, UI_SET_KEYBIT, i);
    for (int i = KEY_A; i <= KEY_L; i++)
        ioctl(fd, UI_SET_KEYBIT, i);
    for (int i = KEY_Z; i <= KEY_M; i++)
        ioctl(fd, UI_SET_KEYBIT, i);
    ioctl(fd, UI_SET_KEYBIT, KEY_ENTER);
    ioctl(fd, UI_SET_KEYBIT, KEY_POWER);
    ioctl(fd, UI_SET_KEYBIT, KEY_HOMEPAGE);
    ioctl(fd, UI_SET_KEYBIT, KEY_WAKEUP);
    ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH);

    ioctl(fd, UI_SET_MSCBIT, MSC_SCAN);
    ioctl(fd, UI_SET_ABSBIT, ABS_X);
    ioctl(fd, UI_SET_ABSBIT, ABS_Y);
    /* NO ABS_PRESSURE — avoids EXTERNAL_STYLUS classification */

    struct uinput_user_dev ud = {0};
    snprintf(ud.name, UINPUT_MAX_NAME_SIZE, "T33A-H");
    ud.id.bustype = BUS_BLUETOOTH;  /* match original T33A: EXTERNAL */
    ud.id.vendor  = 0x1234;
    ud.id.product = 0x5678;
    ud.id.version = 1;
    ud.absmin[ABS_X] = 0; ud.absmax[ABS_X] = 3583;
    ud.absmin[ABS_Y] = 0; ud.absmax[ABS_Y] = 3583;
    write(fd, &ud, sizeof(ud));
    ioctl(fd, UI_DEV_CREATE);
    return fd;
}

static void write_pid(void) {
    FILE *f = fopen(PID_FILE, "w");
    if (f) { fprintf(f, "%d\n", getpid()); fclose(f); }
}

static void remove_pid(void) {
    /* Only remove if PID file still contains our own PID.
     * Prevents a dying daemon from deleting a freshly-started daemon's PID. */
    FILE *f = fopen(PID_FILE, "r");
    if (!f) return;
    int pid = 0;
    fscanf(f, "%d", &pid);
    fclose(f);
    if (pid == getpid()) unlink(PID_FILE);
}

static void daemonize(void) {
    pid_t pid = fork();
    if (pid < 0) exit(1);
    if (pid > 0) {
        printf("Daemon started (PID %d)\n", pid);
        exit(0);
    }
    setsid();
    int fd = open("/dev/null", O_RDWR);
    if (fd >= 0) { dup2(fd, 0); dup2(fd, 1); dup2(fd, 2); close(fd); }
}

/* Worker: the actual remap loop. Runs as child of supervisor. */
static int run_worker(void) {
    signal(SIGINT,  cleanup);
    signal(SIGTERM, cleanup);
    signal(SIGHUP,  SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    /* Boost to real-time priority for minimal input latency */
    struct sched_param sp = { .sched_priority = 1 };
    if (sched_setscheduler(0, SCHED_FIFO, &sp) < 0)
        log_event("warn: SCHED_FIFO failed (not root?) — continuing with normal priority");
    else
        log_event("SCHED_FIFO priority set");

    write_status("waiting");
    heartbeat("started");
    load_config();
    log_event("worker started");

    time_t last_hb = time(NULL);
    int find_fail_logged = 0;     /* throttle find_device failure log */
    time_t last_find_fail_log = 0;

    while (running) {
        int infd = find_device();
        if (infd < 0) {
            time_t now = time(NULL);
            if (now - last_hb >= HEARTBEAT_SEC) {
                heartbeat("waiting:no_device");
                last_hb = now;
            }
            /* Log find_device failure once per 5 minutes — sustained "T33A invisible" */
            if (!find_fail_logged || now - last_find_fail_log >= 300) {
                log_event("warn: T33A device not found in /dev/input — BLE peripheral invisible");
                find_fail_logged = 1;
                last_find_fail_log = now;
            }
            usleep(500000);
            continue;
        }
        find_fail_logged = 0;  /* reset once we see device again */

        if (ioctl(infd, EVIOCGRAB, 1) < 0) {
            log_event("warn: EVIOCGRAB failed — device busy or vanished");
            close(infd);
            usleep(500000);
            continue;
        }

        int uifd = create_uinput();
        if (uifd < 0) {
            log_event("error: create_uinput failed — /dev/uinput permission?");
            ioctl(infd, EVIOCGRAB, 0);
            close(infd);
            usleep(500000);
            continue;
        }

        write_status("active");
        heartbeat("active");
        last_hb = time(NULL);
        log_event("BLE connected — remapping active");

        /* remap loop with select() — 60s timeout for heartbeat even when idle */
        struct input_event ev;
        int active_break = 0;
        while (running && !active_break) {
            fd_set rfds;
            FD_ZERO(&rfds);
            FD_SET(infd, &rfds);
            struct timeval tv = { .tv_sec = HEARTBEAT_SEC, .tv_usec = 0 };
            int sret = select(infd + 1, &rfds, NULL, NULL, &tv);
            if (sret < 0) {
                if (errno == EINTR) continue;
                log_event("warn: select() error — breaking remap loop");
                break;
            }
            if (sret == 0) {
                /* idle timeout — heartbeat */
                heartbeat("active:idle");
                last_hb = time(NULL);
                continue;
            }
            ssize_t n = read(infd, &ev, sizeof(ev));
            if (n != sizeof(ev)) {
                /* EOF or error — device likely disconnected */
                if (n < 0) log_event("warn: read() error — device gone");
                break;
            }
            time_t now = time(NULL);
            if (now - last_hb >= HEARTBEAT_SEC) {
                heartbeat("active");
                last_hb = now;
            }

            if (ev.type == EV_MSC && ev.code == MSC_SCAN) {
                /* Drop MSC_SCAN — stale scan codes (e.g. consumer power 0x000c0030)
                 * confuse Android's InputReader into misidentifying remapped keys */
                continue;
            }
            if (ev.type == EV_KEY) {
                int orig_code = ev.code;
                /* Tap mapping: inject screen touch instead of key */
                mapping_t *tap_map = find_tap(orig_code);
                if (tap_map) {
                    if (ev.value == 1) emit_tap(tap_map->tap_x, tap_map->tap_y);
                    continue;  /* suppress key up too */
                }
                ev.code = remap_key(orig_code);
                /* Wakeup: emit KEY_WAKEUP before key to counteract power-key screen-off */
                if (is_wakeup(orig_code) && ev.value == 1) {
                    emit_event(uifd, EV_KEY, KEY_WAKEUP, 1);
                    emit_event(uifd, EV_SYN, SYN_REPORT, 0);
                    emit_event(uifd, EV_KEY, KEY_WAKEUP, 0);
                    emit_event(uifd, EV_SYN, SYN_REPORT, 0);
                    usleep(80000);  /* 80ms — wait for screen-on before key dispatch */
                }
                /* Double-click: on key down, emit two full clicks and suppress further events */
                if (is_double_click(orig_code) && ev.value == 1) {
                    emit_double_click(uifd, ev.code);
                    continue;  /* skip original down event */
                }
                if (is_double_click(orig_code) && ev.value == 0) {
                    continue;  /* suppress key up — already sent in double_click */
                }
            }
            if (write(uifd, &ev, sizeof(ev)) < 0) {
                log_event("warn: write to uinput failed — breaking remap loop");
                active_break = 1;
            }
        }

        /* device disconnected — cleanup and retry */
        ioctl(uifd, UI_DEV_DESTROY);
        close(uifd);
        ioctl(infd, EVIOCGRAB, 0);
        close(infd);

        write_status("waiting");
        heartbeat("waiting:disconnected");
        last_hb = time(NULL);
        log_event("BLE disconnected — waiting for reconnect");
        usleep(200000);
    }

    write_status("stopped");
    heartbeat("stopped");
    log_event("worker stopped");
    return 0;
}

/* Supervisor: forks worker, restarts on unexpected death. */
static void run_supervisor(void) {
    signal(SIGINT,  supervisor_cleanup);
    signal(SIGTERM, supervisor_cleanup);
    signal(SIGHUP,  SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    while (running) {
        child_pid = fork();
        if (child_pid < 0) { sleep(RESTART_DELAY); continue; }

        if (child_pid == 0) {
            /* child = worker */
            _exit(run_worker());
        }

        /* parent = supervisor: wait for worker */
        int status;
        waitpid(child_pid, &status, 0);
        child_pid = 0;

        if (!running) break;

        /* worker died unexpectedly — restart after delay */
        write_status("restarting");
        log_event("worker died — restarting in 3s");
        sleep(RESTART_DELAY);
    }
}

int main(int argc, char **argv) {
    /* stop command */
    if (argc > 1 && strcmp(argv[1], "stop") == 0) {
        FILE *f = fopen(PID_FILE, "r");
        if (!f) { fprintf(stderr, "Not running\n"); return 1; }
        int pid; fscanf(f, "%d", &pid); fclose(f);
        if (kill(pid, SIGTERM) == 0) {
            printf("Stopped (PID %d)\n", pid);
            remove_pid();
        } else {
            perror("kill"); remove_pid();
        }
        return 0;
    }

    /* status command */
    if (argc > 1 && strcmp(argv[1], "status") == 0) {
        FILE *f = fopen(PID_FILE, "r");
        if (!f) { printf("Not running\n"); return 1; }
        int pid; fscanf(f, "%d", &pid); fclose(f);
        if (kill(pid, 0) == 0) printf("Running (PID %d)\n", pid);
        else { printf("Not running (stale PID)\n"); remove_pid(); }
        return 0;
    }

    /* foreground mode — run worker directly (no supervisor) */
    if (argc > 1 && strcmp(argv[1], "fg") == 0)
        return run_worker();

    /* daemon mode: daemonize → supervisor → worker */
    daemonize();
    write_pid();
    log_event("daemon started (supervisor mode)");
    run_supervisor();
    write_status("stopped");
    log_event("daemon stopped");
    remove_pid();
    return 0;
}

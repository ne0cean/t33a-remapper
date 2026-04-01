#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <time.h>
#include <sys/wait.h>
#include <linux/input.h>
#include <linux/uinput.h>

#define DEVICE_NAME "T33A"
#define PID_FILE    "/data/local/tmp/t33a.pid"
#define STATUS_FILE "/data/local/tmp/t33a.status"
#define LOG_FILE    "/sdcard/Download/t33a.log"
#define RESTART_DELAY 1
#define LOG_MAX_LINES 200

static volatile int running = 1;
static volatile pid_t child_pid = 0;

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

static int remap_key(int code) {
    switch (code) {
        case KEY_HOMEPAGE: return KEY_1;
        case KEY_ENTER:    return KEY_0;
        case KEY_POWER:    return KEY_H;
        default:           return code;
    }
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

static void remove_pid(void) { unlink(PID_FILE); }

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

    write_status("waiting");
    log_event("worker started");

    while (running) {
        int infd = find_device();
        if (infd < 0) { usleep(500000); continue; }

        if (ioctl(infd, EVIOCGRAB, 1) < 0) { close(infd); usleep(500000); continue; }

        int uifd = create_uinput();
        if (uifd < 0) { ioctl(infd, EVIOCGRAB, 0); close(infd); usleep(500000); continue; }

        write_status("active");
        log_event("BLE connected — remapping active");

        /* remap loop */
        struct input_event ev;
        while (running && read(infd, &ev, sizeof(ev)) == sizeof(ev)) {
            if (ev.type == EV_KEY)
                ev.code = remap_key(ev.code);
            if (write(uifd, &ev, sizeof(ev)) < 0) break;
        }

        /* device disconnected — cleanup and retry */
        ioctl(uifd, UI_DEV_DESTROY);
        close(uifd);
        ioctl(infd, EVIOCGRAB, 0);
        close(infd);

        write_status("waiting");
        log_event("BLE disconnected — waiting for reconnect");
        usleep(200000);
    }

    write_status("stopped");
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

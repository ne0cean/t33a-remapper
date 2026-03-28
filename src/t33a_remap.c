#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <linux/input.h>
#include <linux/uinput.h>

#define DEVICE_NAME "T33A"
#define PID_FILE    "/data/local/tmp/t33a.pid"

static volatile int running = 1;

static void cleanup(int sig) { (void)sig; running = 0; }

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
    for (int i = 0; i < KEY_MAX; i++)
        ioctl(fd, UI_SET_KEYBIT, i);
    ioctl(fd, UI_SET_MSCBIT, MSC_SCAN);
    ioctl(fd, UI_SET_ABSBIT, ABS_X);
    ioctl(fd, UI_SET_ABSBIT, ABS_Y);
    ioctl(fd, UI_SET_ABSBIT, ABS_PRESSURE);

    struct uinput_user_dev ud = {0};
    snprintf(ud.name, UINPUT_MAX_NAME_SIZE, "T33A-remap");
    ud.id.bustype = BUS_VIRTUAL;
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

    /* foreground mode */
    int fg = (argc > 1 && strcmp(argv[1], "fg") == 0);

    signal(SIGINT,  cleanup);
    signal(SIGTERM, cleanup);

    if (!fg) daemonize();
    write_pid();

    /* main loop: reconnect when T33A appears/disappears */
    while (running) {
        int infd = find_device();
        if (infd < 0) { sleep(2); continue; }

        if (ioctl(infd, EVIOCGRAB, 1) < 0) { close(infd); sleep(2); continue; }

        int uifd = create_uinput();
        if (uifd < 0) { ioctl(infd, EVIOCGRAB, 0); close(infd); sleep(2); continue; }

        /* remap loop */
        struct input_event ev;
        while (running && read(infd, &ev, sizeof(ev)) == sizeof(ev)) {
            if (ev.type == EV_KEY)
                ev.code = remap_key(ev.code);
            write(uifd, &ev, sizeof(ev));
        }

        /* device disconnected — cleanup and retry */
        ioctl(uifd, UI_DEV_DESTROY);
        close(uifd);
        ioctl(infd, EVIOCGRAB, 0);
        close(infd);
        sleep(1);
    }

    remove_pid();
    return 0;
}

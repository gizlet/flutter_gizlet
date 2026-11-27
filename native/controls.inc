#include <fcntl.h>
#include <glob.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

struct gizlet_controls {
    struct flutterpi *flutterpi;
    bool swap;
    bool held[6];
    int hats[2];
};

static void gizlet_key(struct gizlet_controls *controls, unsigned index, int value) {
    static const uint64_t physical[] = {0x70050, 0x7004f, 0x70052, 0x70051, 0x70028, 0x70029};
    static const uint64_t logical[] = {
        0x00100000302, 0x00100000303, 0x00100000304, 0x00100000301, 0x0010000000d, 0x0010000001b
    };
    if (value < 0 || value > 2 || (value != 2 && controls->held[index] == (value == 1)) ||
        (value == 2 && !controls->held[index])) {
        return;
    }
    controls->held[index] = value != 0;
    struct flutterpi *flutterpi = controls->flutterpi;
    const FlutterKeyEvent event = {
        .struct_size = sizeof(event),
        .timestamp = flutterpi->flutter.procs.GetCurrentTime() / 1000.0,
        .type = value == 0 ? kFlutterKeyEventTypeUp :
                value == 1 ? kFlutterKeyEventTypeDown : kFlutterKeyEventTypeRepeat,
        .physical = physical[index],
        .logical = logical[index],
    };
    flutterpi->flutter.procs.SendKeyEvent(flutterpi->flutter.engine, &event, NULL, NULL);
}

static int gizlet_handle_controls(sd_event_source *source, int fd, uint32_t events, void *userdata) {
    struct gizlet_controls *controls = userdata;
    struct input_event event;
    if (events & (EPOLLHUP | EPOLLERR)) {
        for (unsigned index = 0; index < 6; ++index) gizlet_key(controls, index, 0);
        return sd_event_source_set_enabled(source, SD_EVENT_OFF);
    }
    while (read(fd, &event, sizeof(event)) == sizeof(event)) {
        if (event.type == EV_KEY) {
            switch (event.code) {
                case BTN_DPAD_LEFT: gizlet_key(controls, 0, event.value); break;
                case BTN_DPAD_RIGHT: gizlet_key(controls, 1, event.value); break;
                case BTN_DPAD_UP: gizlet_key(controls, 2, event.value); break;
                case BTN_DPAD_DOWN: gizlet_key(controls, 3, event.value); break;
                case BTN_EAST: gizlet_key(controls, controls->swap ? 5 : 4, event.value); break;
                case BTN_SOUTH: gizlet_key(controls, controls->swap ? 4 : 5, event.value); break;
            }
        } else if (event.type == EV_ABS && (event.code == ABS_HAT0X || event.code == ABS_HAT0Y)) {
            unsigned axis = event.code - ABS_HAT0X;
            int previous = controls->hats[axis];
            if (previous != event.value) {
                if (previous != 0) gizlet_key(controls, axis * 2 + (previous > 0), 0);
                if (event.value != 0) gizlet_key(controls, axis * 2 + (event.value > 0), 1);
                controls->hats[axis] = event.value;
            }
        }
    }
    return 0;
}

static void gizlet_open_controls(struct flutterpi *flutterpi) {
    if (getenv("GIZLET_APP_DIR") == NULL) return;
    glob_t devices;
    if (glob("/dev/input/event*", 0, NULL, &devices) != 0) return;
    const char *swap = getenv("GIZLET_SWAP_AB");
    for (size_t index = 0; index < devices.gl_pathc; ++index) {
        unsigned char keys[(KEY_MAX / 8) + 1] = {0};
        int fd = open(devices.gl_pathv[index], O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;
        if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) < 0 ||
            !(keys[BTN_SOUTH / 8] & (1 << (BTN_SOUTH % 8)))) {
            close(fd);
            continue;
        }
        struct gizlet_controls *controls = calloc(1, sizeof(*controls));
        if (controls == NULL) {
            close(fd);
            break;
        }
        controls->flutterpi = flutterpi;
        controls->swap = swap != NULL && strcmp(swap, "1") == 0;
        sd_event_source *source;
        if (sd_event_add_io(flutterpi->event_loop, &source, fd, EPOLLIN,
                            gizlet_handle_controls, controls) < 0) {
            free(controls);
            close(fd);
            continue;
        }
        sd_event_source_set_io_fd_own(source, 1);
        sd_event_source_set_destroy_callback(source, free);
        sd_event_source_set_floating(source, 1);
        sd_event_source_unref(source);
        break;
    }
    globfree(&devices);
}

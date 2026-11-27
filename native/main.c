#include <stdlib.h>
#include <string.h>

int flutterpi_app_main(int argc, char **argv);

int main(int argc, char **argv) {
    const char *bundle = getenv("GIZLET_APP_DIR");
    const char *language = getenv("GIZLET_LANG");
    if (bundle == NULL || bundle[0] == '\0') {
        return flutterpi_app_main(argc, argv);
    }
    if (language != NULL && strcmp(language, "zh-CN") == 0) {
        setenv("LANG", "zh_CN.UTF-8", 1);
    } else {
        setenv("LANG", "en_US.UTF-8", 1);
    }
    char *args[] = {argv[0], "--release", (char *)bundle, NULL};
    return flutterpi_app_main(3, args);
}

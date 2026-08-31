#include "MihomoBridge.h"
#include <bride.h>

extern void hx_release_object(void *object);
extern void hx_free_string(char *value);
extern void hx_protect(void *object, int descriptor);
extern char *hx_resolve_process(
    void *object,
    int protocol_number,
    const char *source,
    const char *target,
    int uid);
extern void hx_result(void *object, const char *value);

void hx_install_bridge(void) {
  release_object_func = hx_release_object;
  free_string_func = hx_free_string;
  protect_func = hx_protect;
  resolve_process_func = hx_resolve_process;
  result_func = hx_result;
}

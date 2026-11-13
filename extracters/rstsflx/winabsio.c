/* Windows build operates on container files. No DOS interrupt or raw-device
 * backend is implied by the Unix/DOS sources shipped with this utility.
 */
#include <stdio.h>
#include <string.h>
#include "flx.h"
#include "absio.h"

void absname(const char *name)
{
    if (!strncmp(name, "\\\\.\\", 4) || !strncmp(name, "\\\\?\\", 4)) {
        printf("Windows device namespace paths are not supported by this build\n");
        rabort(NOMSG);
    }
}
int absopen(const char *name, const char *mode)
{
    (void)name; (void)mode;
    rabort(INTERNAL);
    return -1;
}
void absseek(long block) { (void)block; rabort(INTERNAL); }
void absclose(void) { rabort(INTERNAL); }
long absread(long block, long count, void *buffer)
{
    (void)block; (void)count; (void)buffer;
    rabort(INTERNAL);
    return -1;
}
long abswrite(long block, long count, void *buffer)
{
    (void)block; (void)count; (void)buffer;
    rabort(INTERNAL);
    return -1;
}

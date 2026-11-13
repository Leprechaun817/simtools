/* Standard console line input also accepts redirected scripts. Windows supplies
 * cooked console editing; Readline completion and persistent history are absent.
 */
#include <stdio.h>
#include <stdlib.h>
#include "flx.h"
#include "winconsole.h"

char *flx_readline(const char *prompt)
{
    size_t size = 256, used = 0;
    char *line = malloc(size), *grown;
    int ch;
    if (line == NULL) rabort(NOMEM);
    fputs(prompt, stdout);
    fflush(stdout);
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (used + 1 == size) {
            grown = realloc(line, size * 2);
            if (grown == NULL) { free(line); rabort(NOMEM); }
            line = grown;
            size *= 2;
        }
        line[used++] = (char)ch;
    }
    if (ch == EOF && used == 0) { free(line); return NULL; }
    if (used && line[used - 1] == '\r') --used;
    line[used] = '\0';
    return line;
}

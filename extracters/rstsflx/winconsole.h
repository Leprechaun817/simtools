/* Native console fallback; GNU Readline remains available to existing builds. */
#ifndef FLX_WINCONSOLE_H
#define FLX_WINCONSOLE_H
char *flx_readline(const char *prompt);
#define readline flx_readline
#define add_history(line) ((void)(line))
#endif

/* Windows build of nova (MinGW-w64): the POSIX calls of nova.c mapped to Win32. Force-included by
   win/build.sh; win/sys/*.h and win/dlfcn.h are empty so the POSIX #includes still resolve.
   ponytail: one process, no parallel jobs (nova_par.li forks; fork() failing makes the parent run
   each job itself, same output). Parallel Windows jobs would need CreateProcess replicas like the web build. */
#ifndef NOVA_WIN_H
#define NOVA_WIN_H
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* dlopen: "libwebp.so.7" -> tries the name, then "libwebp.dll", then "libwebp-7.dll" (MSYS2 names) */
#define RTLD_NOW 2
#define RTLD_LOCAL 0
static void *dlopen(const char *name, int flags) {
  char b[256];
  const char *so = strstr(name, ".so");
  void *h;
  (void)flags;
  if (strstr(name, ".dylib") || !so || so - name > 200) return NULL;
  sprintf(b, "%.*s.dll", (int)(so - name), name);
  if ((h = LoadLibraryA(b)) != NULL) return h;
  if (so[3] == '.') {
    sprintf(b, "%.*s-%s.dll", (int)(so - name), name, so + 4);
    if ((h = LoadLibraryA(b)) != NULL) return h;
  }
  return strcmp(name, "libz.so.1") == 0 ? LoadLibraryA("zlib1.dll") : NULL;
}
static void *dlsym(void *h, const char *sym) { return h ? (void *)GetProcAddress((HMODULE)h, sym) : NULL; }
static char *dlerror(void) { return "library not found"; }

/* no fork: jobs run in this process */
static int fork(void) { return -1; }
static int wait(int *s) { (void)s; return -1; }
static int waitpid(int p, int *s, int o) { (void)p; (void)s; (void)o; return -1; }
#define WNOHANG 1
#define _SC_NPROCESSORS_ONLN 84
static long sysconf(int n) { (void)n; return 1; }

/* shared memory for the (absent) child processes: plain zeroed memory */
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1
#define MAP_ANONYMOUS 0x20
#define MAP_NORESERVE 0x4000
#define MAP_FAILED ((void *)-1)
static void *mmap(void *a, size_t n, int p, int f, int fd, long o) {
  void *m;
  (void)a; (void)p; (void)f; (void)fd; (void)o;
  m = VirtualAlloc(NULL, n, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
  return m ? m : MAP_FAILED;
}
static int munmap(void *a, size_t n) { (void)n; return VirtualFree(a, 0, MEM_RELEASE) ? 0 : -1; }

/* terminal width (lib/system/dev.li): unknown, callers fall back to 80 columns */
#define TIOCGWINSZ 0x5413
struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
static int ioctl(int fd, unsigned long r, void *w) { (void)fd; (void)r; (void)w; return -1; }
#endif

#if defined(__linux__) || defined(__APPLE__) || defined(__FreeBSD__)

  // #include <errno.h>
  #include <signal.h> //killpg
  #include <unistd.h> //getpgid

#else

  #error "unsupported platform"

#endif

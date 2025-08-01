#include <SDL3/SDL.h>
#include <sys/inotify.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>

#include "dirmonitor.h"

struct dirmonitor_internal {
  int fd;
  // a pipe is used to wake the thread in case of exit
  int sig[2];
};


static struct dirmonitor_internal* init_dirmonitor() {
  struct dirmonitor_internal* monitor = SDL_calloc(1, sizeof(struct dirmonitor_internal));
  monitor->fd = inotify_init();
  pipe(monitor->sig);
  fcntl(monitor->sig[0], F_SETFD, FD_CLOEXEC);
  fcntl(monitor->sig[1], F_SETFD, FD_CLOEXEC);
  return monitor;
}


static void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  close(monitor->fd);
  close(monitor->sig[0]);
  close(monitor->sig[1]);
}


static int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length) {
  struct pollfd fds[2] = { { .fd = monitor->fd, .events = POLLIN | POLLERR, .revents = 0 }, { .fd = monitor->sig[0], .events = POLLIN | POLLERR, .revents = 0 } };
  poll(fds, 2, -1);
  return read(monitor->fd, buffer, length);
}


static int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length, int (*change_callback)(int, const char*, void*), void* data) {
  for (struct inotify_event* info = (struct inotify_event*)buffer; (char*)info < buffer + length; info = (struct inotify_event*)((char*)info + sizeof(struct inotify_event)))
    change_callback(info->wd, NULL, data);
  return 0;
}


static int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  return inotify_add_watch(monitor->fd, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MODIFY | IN_MOVED_TO);
}


static void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  inotify_rm_watch(monitor->fd, fd);
}


static int get_mode_dirmonitor() { return 2; }

struct dirmonitor_backend dirmonitor_inotify = {
  .name = "inotify",
  .init = init_dirmonitor,
  .deinit = deinit_dirmonitor,
  .get_changes = get_changes_dirmonitor,
  .translate_changes = translate_changes_dirmonitor,
  .add = add_dirmonitor,
  .remove = remove_dirmonitor,
  .get_mode = get_mode_dirmonitor,
};

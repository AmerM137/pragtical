#include "api.h"
#include "lua.h"
#include <SDL3/SDL.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include "dirmonitor/dirmonitor.h"

static unsigned int DIR_EVENT_TYPE = 0;

struct dirmonitor {
  SDL_Thread* thread;
  SDL_Mutex* mutex;
  char buffer[64512];
  volatile int length;
  struct dirmonitor_backend* backend;
  struct dirmonitor_internal* internal;
};


static struct dirmonitor_backend* const backends[] = {
#ifdef DIRMONITOR_INOTIFY
  &dirmonitor_inotify,
#endif
#ifdef DIRMONITOR_FSEVENTS
  &dirmonitor_fsevents,
#endif
#ifdef DIRMONITOR_KQUEUE
  &dirmonitor_kqueue,
#endif
#ifdef DIRMONITOR_INODEWATCHER
  &dirmonitor_inodewatcher,
#endif
#ifdef DIRMONITOR_WIN32
  &dirmonitor_win32,
#endif
#ifdef DIRMONITOR_DUMMY
  &dirmonitor_dummy,
#endif
  NULL
};

static struct dirmonitor_backend* find_backend(const char* name)
{
  struct dirmonitor_backend* const * backend = backends;
  while (*backend)
  {
    if (!name || !strcmp((*backend)->name, name))
      return *backend;
    ++backend;
  }

  return NULL;
}

static int f_check_dir_callback(int watch_id, const char* path, void* L) {
  // using absolute indices from f_dirmonitor_check (2: callback, 3: error_callback, 4: watch_id notified table)

  // Check if we already notified about this watch
  lua_rawgeti(L, 4, watch_id);
  bool skip = !lua_isnoneornil(L, -1);
  lua_pop(L, 1);
  if (skip) return 0;

  // Set watch as notified
  lua_pushboolean(L, true);
  lua_rawseti(L, 4, watch_id);

  // Prepare callback call
  lua_pushvalue(L, 2);
  if (path)
    lua_pushlstring(L, path, watch_id);
  else
    lua_pushnumber(L, watch_id);

  int result = 0;
  if (lua_pcall(L, 1, 1, 3) == LUA_OK)
    result = lua_toboolean(L, -1);
  lua_pop(L, 1);
  return !result;
}


static int dirmonitor_check_thread(void* data) {
  struct dirmonitor* monitor = data;
  while (monitor->length >= 0) {
    if (monitor->length == 0) {
      int result = monitor->backend->get_changes(monitor->internal, monitor->buffer, sizeof(monitor->buffer));
      SDL_LockMutex(monitor->mutex);
      if (monitor->length == 0)
        monitor->length = result;
      SDL_UnlockMutex(monitor->mutex);
    }
    SDL_Delay(1);
    SDL_Event event = { .type = DIR_EVENT_TYPE };
    SDL_PushEvent(&event);
  }
  return 0;
}


static int f_dirmonitor_new(lua_State* L) {
  if (DIR_EVENT_TYPE == 0)
    DIR_EVENT_TYPE = SDL_RegisterEvents(1);
  const char* name = luaL_optstring(L, 1, NULL);
  struct dirmonitor_backend* backend = find_backend(name);
  if (!backend)
    return luaL_error(L, "Unable to find dirmonitor '%s'", name);
  struct dirmonitor* monitor = lua_newuserdata(L, sizeof(struct dirmonitor));
  luaL_setmetatable(L, API_TYPE_DIRMONITOR);
  memset(monitor, 0, sizeof(struct dirmonitor));
  monitor->mutex = SDL_CreateMutex();
  monitor->backend = backend;
  monitor->internal = monitor->backend->init();
  return 1;
}


static int f_dirmonitor_gc(lua_State* L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  SDL_LockMutex(monitor->mutex);
  monitor->length = -1;
  monitor->backend->deinit(monitor->internal);
  SDL_UnlockMutex(monitor->mutex);
  SDL_WaitThread(monitor->thread, NULL);
  SDL_free(monitor->internal);
  SDL_DestroyMutex(monitor->mutex);
  return 0;
}


static int f_dirmonitor_watch(lua_State *L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  lua_pushnumber(L, monitor->backend->add(monitor->internal, luaL_checkstring(L, 2)));
  if (!monitor->thread)
    monitor->thread = SDL_CreateThread(dirmonitor_check_thread, "dirmonitor_check_thread", monitor);
  return 1;
}


static int f_dirmonitor_unwatch(lua_State *L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  monitor->backend->remove(monitor->internal, lua_tonumber(L, 2));
  return 0;
}


static int f_noop(lua_State *L) { return 0; }


static int f_dirmonitor_check(lua_State* L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  luaL_checktype(L, 2, LUA_TFUNCTION);
  if (!lua_isnoneornil(L, 3)) {
    luaL_checktype(L, 3, LUA_TFUNCTION);
  } else {
    lua_settop(L, 2);
    lua_pushcfunction(L, f_noop);
  }
  lua_settop(L, 3);

  SDL_LockMutex(monitor->mutex);
  if (monitor->length < 0)
    lua_pushnil(L);
  else if (monitor->length > 0) {
    // Create a table for keeping track of what watch ids were notified in this check,
    // so that we avoid notifying multiple times.
    lua_newtable(L);
    if (monitor->backend->translate_changes(monitor->internal, monitor->buffer, monitor->length, f_check_dir_callback, L) == 0)
      monitor->length = 0;
    lua_pushboolean(L, 1);
  } else
    lua_pushboolean(L, 0);
  SDL_UnlockMutex(monitor->mutex);
  return 1;
}


static int f_dirmonitor_mode(lua_State* L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  int mode = monitor->backend->get_mode();
  if (mode == 1)
    lua_pushstring(L, "single");
  else
    lua_pushstring(L, "multiple");
  return 1;
}

static int f_dirmonitor_backends(lua_State* L) {
  const size_t s = (sizeof(backends) / sizeof(backends[0])) - 1;

  lua_createtable(L, 0, s);
  for (size_t i = 0; i < s; ++i) {
    lua_pushnumber(L, i+1);
    lua_pushstring(L, backends[i]->name);
    lua_settable(L, -3);
  }

  return 1;
}

static const luaL_Reg dirmonitor_lib[] = {
  { "new",      f_dirmonitor_new         },
  { "__gc",     f_dirmonitor_gc          },
  { "watch",    f_dirmonitor_watch       },
  { "unwatch",  f_dirmonitor_unwatch     },
  { "check",    f_dirmonitor_check       },
  { "mode",     f_dirmonitor_mode        },
  { "backends", f_dirmonitor_backends    },
  {NULL, NULL}
};


int luaopen_dirmonitor(lua_State* L) {
  luaL_newmetatable(L, API_TYPE_DIRMONITOR);
  luaL_setfuncs(L, dirmonitor_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}

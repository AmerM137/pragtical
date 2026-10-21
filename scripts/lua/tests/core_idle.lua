local test = require "core.test"
local core = require "core"
local common = require "core.common"

test.describe("core idle scheduling", function()
  test.after_each(function(c)
    if c.child and c.child:running() then
      c.child:kill()
      c.child:wait(1000, 0.01)
    end
    if c.directory then common.rm(c.directory, true) end
  end)

  local function run_child(c, source, callback_rate)
    c.directory = core.temp_filename()
    test.ok(common.mkdirp(c.directory))
    local script = c.directory .. PATHSEP .. "idle.lua"
    local file = assert(io.open(script, "w"))
    file:write(source)
    file:close()
    c.child = assert(process.start({ EXEFILE, "run", "-n", script }, {
      stdout = process.REDIRECT_PIPE, stderr = process.REDIRECT_STDOUT,
      env = {
        PRAGTICAL_USERDIR = c.directory .. PATHSEP .. "user",
        PRAGTICAL_RENDERER = "surface",
        SDL_VIDEO_DRIVER = "dummy", SDL_AUDIO_DRIVER = "dummy",
        SDL_MAIN_CALLBACK_RATE = callback_rate
      }
    }))
    local status = c.child:wait(10000, 0.01)
    test.equal(status, 0, "idle subprocess failed: " .. (c.child:read_stdout() or ""))
  end

  test.test("idle deadlines do not renew the unfocused grace period", function(c)
    run_child(c, [=[
local core = require "core"
local config = require "core.config"
local run = core.run
core.run = function()
  run()
  local ok, err = xpcall(function()
    local now = system.get_time()
    local focused, pending = true, false
    local steps, foreground, background = 0, 0, 0
    system.get_time = function() return now end
    system.window_has_focus = function() return focused end
    system.has_pending_events = function() return pending end
    config.fps, core.fps, core.co_max_time = 60, 60, 0.012
    core.threads, core.background_threads, core.redraw = {}, 0, false
    core.step = function()
      steps = steps + 1
      core.redraw, pending = false, false
      return false
    end
    local function iterate()
      for _ = 1, 20 do
        local running, wait = core.run_step()
        assert(running and wait >= 0, "invalid scheduler result")
        if wait > 0 then return wait end
        now = now + 0.000001
      end
      error("scheduler kept returning an immediate deadline")
    end
    iterate()
    focused, now = false, now + 6
    core.add_thread(function()
      while true do foreground = foreground + 1; coroutine.yield(0.1) end
    end)
    core.add_background_thread(function()
      while true do background = background + 1; coroutine.yield(0.25) end
    end)
    assert(iterate() > 0.2, "idle wait was capped to a frame")
    assert(background > 0 and foreground == 0, "wrong tasks ran while idle")
    local previous_steps = steps
    now = now + 1
    iterate()
    assert(steps == previous_steps and foreground == 0, "timer renewed the grace period")
    pending = true
    now = now + 1
    iterate()
    assert(steps > previous_steps and foreground > 0, "input did not resume foreground work")
    now = now + 6
    iterate()
    previous_steps = steps
    focused = true
    iterate()
    assert(steps > previous_steps, "focus gain did not resume updates immediately")
    focused, now, core.redraw = false, now + 6, true
    previous_steps = steps
    iterate()
    assert(steps > previous_steps, "redraw request was ignored while unfocused")
    core.quit_request = true
    assert(core.run_step() == false, "idle quit request was ignored")
    core.quit_request = false
    core.threads, core.background_threads = {}, 0
    now = now + 6
    assert(iterate() == math.huge, "empty idle loop did not wait for input")
    now = now + 1
    assert(iterate() == math.huge, "empty idle loop renewed its grace period")
  end, debug.traceback)
  if not ok then print(err) end
  core.quit(true, ok and 0 or 1)
  core.run_step = function() return false end
end
]=])
  end)

  for _, callback_rate in ipairs { "0", "waitevent" } do
    test.test("background jobs wake and restart with callback rate " .. callback_rate, function(c)
      run_child(c, [=[
local core = require "core"
local config = require "core.config"
config.fps, config.auto_fps = 60, false
local clock = system.get_time
local offset, calls, jobs = 0, 0, 0
local start = clock()
system.get_time = function() return clock() + offset end
system.window_has_focus = function() return false end
core.threads, core.background_threads, core.redraw = {}, 0, false
core.step = function()
  for _ in system.poll_event do end
  core.redraw = false
  return false
end
local ready = thread.get_channel("idle-worker")
thread.create("idle-worker", function()
  local started = system.get_time()
  for _ = 1, 4 do system.sleep(0.0005) end
  thread.get_channel("idle-worker"):push(system.get_time() - started >= 0.002)
end)
core.add_background_thread(function()
  while true do
    jobs = jobs + 1
    if jobs == 8 then
      assert(clock() - start >= 0.2, "coroutine deadlines ran too early")
      assert(calls < 200, "SDL spun instead of waiting for deadlines")
      assert(ready:first() == true, "native worker sleep lost sub-millisecond precision")
      if RESTARTED then core.quit(true) else core.restart_request = true end
      return
    end
    coroutine.yield(0.04)
  end
end)
local run_step = core.run_step
core.run_step = function()
  calls = calls + 1
  assert(clock() - start < 5, "background jobs did not wake")
  local running, wait = run_step()
  offset = 6 -- expire the unfocused grace period without delaying the test
  return running, wait
end
]=], callback_rate)
    end)
  end
end)

local tffi = require("trig.native")
local ffi = require("ffi")

local M = {}

M.config = {
  -- dir holding libtrig (and the trig CLI); nil = search rtp, then PATH
  bin_dir = nil,
  -- index the git root of cwd on VimEnter
  auto_index = true,
  -- hits per keystroke in :TrigLive (verify stops early past this)
  live_max = 2000,
  qf_max = 10000,
  -- poll interval while indexing, ms
  poll_ms = 200,
  fzf_options = "--no-hscroll --color=dark,fg+:219,bg+:16,info:39,hl+:206 --pointer=• --delimiter=: --nth=4..",
}

---@type table<string, ffi.cdata*> root -> handle
local engines = {}

local function notify(msg, level)
  vim.notify("trig: " .. msg, level or vim.log.levels.INFO)
end

local function lib()
  if not tffi.load(M.config.bin_dir) then
    error("trig: " .. tffi.load_error)
  end
  return tffi.lib
end

function M.root(path)
  return vim.fs.root(path or vim.fn.getcwd(), ".git") or vim.fn.getcwd()
end

function M.engine(root)
  root = vim.fn.resolve(root or M.root())
  local h = engines[root]
  if h then
    return h, root
  end
  h = lib().trig_open(root, nil)
  if h == nil then
    error("trig: open failed: " .. tffi.last_error())
  end
  h = ffi.gc(h, lib().trig_close)
  engines[root] = h
  return h, root
end

--- Engine owning `path`, only if one is already open (never opens on BufWritePost).
local function owner(path)
  path = vim.fn.resolve(path)
  local best, best_len
  for root, h in pairs(engines) do
    if (path == root or vim.startswith(path, root .. "/")) and (not best_len or #root > best_len) then
      best, best_len = h, #root
    end
  end
  return best
end

local timers = {}

function M.index(root, opts)
  opts = opts or {}
  local h
  h, root = M.engine(root)
  local started = lib().trig_index_async(h, 1)
  if started == 0 then
    return notify("already indexing " .. root)
  elseif started < 0 then
    return notify("index failed: " .. tffi.last_error(), vim.log.levels.ERROR)
  end
  local t0 = vim.uv.hrtime()
  if timers[root] then
    timers[root]:stop()
  end
  local timer = vim.uv.new_timer()
  timers[root] = timer
  timer:start(M.config.poll_ms, M.config.poll_ms, vim.schedule_wrap(function()
    local st = tffi.status(h)
    if st.state == "ready" or st.state == "error" then
      timer:stop()
      timer:close()
      timers[root] = nil
      if st.state == "error" then
        notify("index failed: " .. tffi.last_error(), vim.log.levels.ERROR)
      elseif not opts.quiet or st.total > 0 then
        notify(("indexed %d files in %.1fs"):format(st.total, (vim.uv.hrtime() - t0) / 1e9))
      end
    end
  end))
end

function M.status()
  local lines = {}
  for root, h in pairs(engines) do
    local st = tffi.status(h)
    table.insert(lines, ("%s  [%s %d/%d]  db=%s"):format(root, st.state, st.done, st.total, ffi.string(lib().trig_db_path(h))))
  end
  notify(#lines > 0 and table.concat(lines, "\n") or "no open index")
end

function M.update(path)
  local h = owner(path)
  if h and lib().trig_update(h, path) < 0 then
    notify("update failed: " .. tffi.last_error(), vim.log.levels.WARN)
  end
end

local function parse_flags(bang)
  return bang and tffi.FLAG_FIXED or 0
end

--- :Trig pattern -> quickfix
function M.quickfix(pattern, opts)
  opts = opts or {}
  local h, root = M.engine()
  local t0 = vim.uv.hrtime()
  local out, err = tffi.search(h, pattern, parse_flags(opts.fixed), M.config.qf_max)
  if not out then
    return notify(err, vim.log.levels.ERROR)
  end
  local ms = (vim.uv.hrtime() - t0) / 1e6
  local lines = vim.split(out, "\n", { trimempty = true })
  -- paths are root-relative; make them absolute so cwd doesn't matter
  local prefix = root .. "/"
  for i, l in ipairs(lines) do
    lines[i] = prefix .. l
  end
  vim.fn.setqflist({}, " ", { title = ("Trig %s (%d hits, %.1fms)"):format(pattern, #lines, ms), lines = lines, efm = "%f:%l:%c:%m" })
  if #lines > 0 then
    vim.cmd("copen")
  else
    notify(("no matches for %s (%.1fms)"):format(pattern, ms))
  end
end

--- :TrigLive -> fzf.vim picker, the trig CLI re-runs on every keystroke against the same DB.
function M.live(query, fullscreen)
  local h, root = M.engine()
  local cli = tffi.bin_dir .. "/trig"
  if vim.fn.executable(cli) == 1 and not vim.env.PATH:find(tffi.bin_dir, 1, true) then
    vim.env.PATH = tffi.bin_dir .. ":" .. vim.env.PATH
  end
  local db = ffi.string(lib().trig_db_path(h))
  local prefix = ("trig --root %s --db %s search --color --max %d --"):format(vim.fn.shellescape(root), vim.fn.shellescape(db), M.config.live_max)
  local spec = vim.fn["fzf#vim#with_preview"]({ options = M.config.fzf_options, dir = root })
  vim.fn["fzf#vim#grep2"](prefix, query or "", spec, fullscreen and 1 or 0)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M

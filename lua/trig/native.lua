local ffi = require("ffi")

ffi.cdef([[
typedef struct TrigHandle TrigHandle;
typedef struct { int32_t state; uint64_t done; uint64_t total; } TrigStatus;

uint32_t trig_abi_version(void);

const char *trig_last_error(void);
TrigHandle *trig_open(const char *root, const char *db);
void trig_close(TrigHandle *h);
const char *trig_db_path(const TrigHandle *h);
const char *trig_root(const TrigHandle *h);
int32_t trig_index_async(const TrigHandle *h, int32_t compact);
void trig_status(const TrigHandle *h, TrigStatus *out);
int32_t trig_update(const TrigHandle *h, const char *path);
int32_t trig_remove(const TrigHandle *h, const char *path);
uint8_t *trig_search(const TrigHandle *h, const char *pattern, uint32_t flags, uint32_t max, size_t *out_len);
void trig_free(uint8_t *p, size_t len);
]])

local M = {}

M.ABI_VERSION = 1

local libname = "libtrig." .. (jit.os == "OSX" and "dylib" or "so")

--- Dirs that may hold libtrig: explicit opt, a hood/trig checkout on rtp, the lib next to `trig` on PATH.
local function candidates(bin_dir)
  local dirs = {}
  if bin_dir then
    table.insert(dirs, vim.fn.expand(bin_dir))
  end
  for _, f in ipairs(vim.api.nvim_get_runtime_file("target/release/" .. libname, true)) do
    table.insert(dirs, vim.fs.dirname(f))
  end
  local exe = vim.fn.exepath("trig")
  if exe ~= "" then
    local r = vim.system({ exe, "lib-path" }, { text = true }):wait()
    if r.code == 0 then
      table.insert(dirs, vim.fs.dirname(vim.trim(r.stdout)))
    end
  end
  return dirs
end

local function try(path)
  local ok, lib = pcall(ffi.load, path)
  if not ok then
    return nil, lib
  end
  local okv, v = pcall(function()
    return lib.trig_abi_version()
  end)
  v = okv and tonumber(v) or 0
  if v ~= M.ABI_VERSION then
    return nil, ("%s has ABI v%d, trig.nvim needs v%d: update hood/trig and rebuild"):format(path, v, M.ABI_VERSION)
  end
  return lib
end

--- Finds and loads libtrig once. Returns the lib or nil; M.load_error says why.
function M.load(bin_dir)
  if M.lib or M.load_error then
    return M.lib
  end
  local errs = {}
  for _, dir in ipairs(candidates(bin_dir)) do
    local path = dir .. "/" .. libname
    if vim.uv.fs_stat(path) then
      local lib, err = try(path)
      if lib then
        M.lib, M.bin_dir = lib, dir
        return lib
      end
      table.insert(errs, err)
    end
  end
  M.load_error = #errs > 0 and table.concat(errs, "\n")
    or ("%s not found: add hood/trig to your plugins (build: cargo build --release), put `trig` on PATH, or set bin_dir"):format(libname)
  return nil
end

M.FLAG_IGNORE_CASE = 1
M.FLAG_CASE_SENSITIVE = 2
M.FLAG_FIXED = 4

M.STATE = { [0] = "idle", "walking", "indexing", "compacting", "ready", "error" }

function M.last_error()
  return ffi.string(M.lib.trig_last_error())
end

function M.status(h)
  local st = ffi.new("TrigStatus[1]")
  M.lib.trig_status(h, st)
  return { state = M.STATE[st[0].state] or "?", done = tonumber(st[0].done), total = tonumber(st[0].total) }
end

function M.search(h, pattern, flags, max)
  local len = ffi.new("size_t[1]")
  local p = M.lib.trig_search(h, pattern, flags or 0, max or 0, len)
  if p == nil then
    return nil, M.last_error()
  end
  local s = ffi.string(p, len[0])
  M.lib.trig_free(p, len[0])
  return s
end

return M

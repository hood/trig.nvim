# trig.nvim

Outrageously fast indexed code search for Neovim, on top of [trig](https://github.com/hood/trig) (trigram index in RocksDB, Rust core, NEON). Talks to it over LuaJIT FFI, no RPC.

| linux kernel, 97k files, M1 Pro, warm cache | rg | trig |
|---|---|---|
| `spin_lock_irqsave` (15.9k hits) | 2295ms | 63ms |
| `xa_(load\|store)\(` | 2304ms | 20ms |
| `hello world` | 2236ms | 12ms |
| reindex `kernel/sched/core.c` on save | | 6.5ms |

## Install

The engine lives in [hood/trig](https://github.com/hood/trig), this repo is Lua only. Building trig needs Rust, cmake and `libclang` (Xcode CLT on macOS). First build compiles RocksDB, takes a few minutes.

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "hood/trig.nvim",
  dependencies = { { "hood/trig", build = "cargo build --release" } },
  keys = { { "F", "<cmd>TrigLive<cr>" } },
}
```

Other managers: install both repos and run `cargo build --release` in the `trig` one.

`libtrig` is looked up in this order:

1. `bin_dir` in `setup()`
2. `target/release/` of a `trig` checkout on the runtimepath
3. `trig lib-path`, if `trig` is on `PATH`

A lib built from an incompatible trig version is refused with an error, not loaded.

`:TrigLive` needs [fzf.vim](https://github.com/junegunn/fzf.vim).

## Usage

| | |
|---|---|
| `:TrigLive [query]` | live search in fzf, re-queries the index per keystroke |
| `:Trig {regex}` | results into quickfix (`:Trig!` = fixed string) |
| `:TrigIndex [dir]` | build/refresh the index |
| `:TrigStatus` | index state and DB path |

The git root of cwd gets indexed on startup. After the first run only files whose mtime/size changed are re-read. Saved buffers are re-indexed on `BufWritePost`. Smart case like `rg -S`, `.gitignore` respected, hidden files included, `.git` skipped.

Options:

```lua
require("trig").setup({
  bin_dir = nil,    -- dir holding libtrig and the trig CLI, nil = auto
  auto_index = true,
  live_max = 2000,  -- hits per keystroke in :TrigLive
  qf_max = 10000,
})
```

## Limits

- Files changed outside nvim (e.g. `git checkout`) are picked up on the next startup or `:TrigIndex`, there's no watcher yet.
- While the first index builds, searches only see what's already been flushed.
- Only tested on macOS/aarch64, x86/Linux support is WIP.

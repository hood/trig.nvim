if vim.g.loaded_trig then
  return
end
vim.g.loaded_trig = true

local function trig()
  return require("trig")
end

vim.api.nvim_create_user_command("TrigIndex", function(o)
  trig().index(o.args ~= "" and o.args or nil)
end, { nargs = "?", complete = "dir", desc = "Build/refresh the trigram index" })

vim.api.nvim_create_user_command("TrigStatus", function()
  trig().status()
end, { desc = "Show trig index status" })

vim.api.nvim_create_user_command("Trig", function(o)
  trig().quickfix(o.args, { fixed = o.bang })
end, { nargs = "+", bang = true, desc = "Trig search into quickfix (! = fixed string)" })

vim.api.nvim_create_user_command("TrigLive", function(o)
  trig().live(o.args, o.bang)
end, { nargs = "*", bang = true, desc = "Live trig search in fzf" })

local group = vim.api.nvim_create_augroup("trig", { clear = true })

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  callback = function(ev)
    if vim.bo[ev.buf].buftype == "" and ev.file ~= "" then
      trig().update(vim.api.nvim_buf_get_name(ev.buf))
    end
  end,
})

local function auto_index()
  local t = trig()
  if t.config.auto_index and require("trig.native").load(t.config.bin_dir) and vim.fs.root(vim.fn.getcwd(), ".git") then
    -- reconcile is incremental: only changed files since last run get re-read
    pcall(t.index, nil, { quiet = true })
  end
end

-- Lazy loaders (vim.pack inside VimEnter, etc.) add us after VimEnter already fired.
if vim.v.vim_did_enter == 1 then
  vim.schedule(auto_index)
else
  vim.api.nvim_create_autocmd("VimEnter", { group = group, once = true, callback = auto_index })
end

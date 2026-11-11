-- Starlight via oasis.nvim — upstream switches dark/light on
-- vim.o.background; the background follows the workstation theme pick
-- (~/.local/state/workstation/theme/current/tokens.json), live through a
-- directory watch on the pick.
local pick_dir = vim.fn.expand("~/.local/state/workstation/theme")
local tokens = pick_dir .. "/current/tokens.json"

local function appearance()
	local fd = io.open(tokens, "r")
	if not fd then
		return nil
	end
	local ok, data = pcall(vim.json.decode, fd:read("*a"))
	fd:close()
	if ok and type(data) == "table" and (data.appearance == "dark" or data.appearance == "light") then
		return data.appearance
	end
	return nil
end

local function follow()
	local want = appearance()
	if want and vim.o.background ~= want then
		vim.o.background = want
	end
end

local function watch()
	if vim.fn.isdirectory(pick_dir) == 0 then
		return
	end
	local handle = vim.uv.new_fs_event()
	if handle then
		handle:start(pick_dir, {}, vim.schedule_wrap(follow))
	end
end

local specs = {
	{
		"uhs-robert/oasis.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			-- `style` is the setup contract key (README configuration block);
			-- `light_intensity` 3 is already the upstream default.
			require("oasis").setup({ style = "starlight" })
			follow()
			vim.cmd.colorscheme("oasis-starlight")
			watch()
		end,
	},

	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "oasis-starlight",
		},
	},
}

return specs

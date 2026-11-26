return {
	-- Move lines and visual selections with Alt-j/k.
	{
		"matze/vim-move",
		init = function()
			vim.g.move_map_keys = 0
		end,
		config = function()
			vim.keymap.set("n", "<A-k>", "<Plug>MoveLineUp", { remap = true, silent = true, desc = "Move line up" })
			vim.keymap.set("n", "<A-j>", "<Plug>MoveLineDown", { remap = true, silent = true, desc = "Move line down" })
			vim.keymap.set(
				"x",
				"<A-k>",
				"<Plug>MoveBlockCountLinesUp",
				{ remap = true, silent = true, desc = "Move selection up" }
			)
			vim.keymap.set(
				"x",
				"<A-j>",
				"<Plug>MoveBlockCountLinesDown",
				{ remap = true, silent = true, desc = "Move selection down" }
			)
		end,
	},

	-- Close and rename paired HTML/JSX tags.
	{
		"windwp/nvim-ts-autotag",
		opts = {},
	},

	-- Keep Git operations in Lazygit and use Diffview for visual review/history.
	{
		"sindrets/diffview.nvim",
		cmd = {
			"DiffviewClose",
			"DiffviewFileHistory",
			"DiffviewFocusFiles",
			"DiffviewLog",
			"DiffviewOpen",
			"DiffviewRefresh",
			"DiffviewToggleFiles",
		},
		opts = {
			enhanced_diff_hl = true,
			view = {
				merge_tool = {
					layout = "diff4_mixed",
				},
			},
		},
		keys = {
			{ "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview working tree" },
			{ "<leader>gV", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview branch history" },
			{ "<leader>gF", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview file history" },
			{ "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Close Diffview" },
		},
	},

	-- Show all declaration kinds in LSP symbol pickers (`<leader>ss`/`<leader>sS`).
	-- LazyVim's default kind_filter drops Constant/Variable/TypeParameter/EnumMember,
	-- hiding `const`/`let`/`type` exports (most of a TS codebase's symbols) that
	-- VS Code's Ctrl+T workspace symbol search includes.
	{
		"LazyVim/LazyVim",
		opts = {
			kind_filter = {
				default = {
					"Class",
					"Constant",
					"Constructor",
					"Enum",
					"EnumMember",
					"Field",
					"Function",
					"Interface",
					"Method",
					"Module",
					"Namespace",
					"Package",
					"Property",
					"Struct",
					"Trait",
					"TypeParameter",
					"Variable",
					},
				},
		},
	},
}

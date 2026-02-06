local config = require("dbab.config")

describe("config", function()
  -- Reset config before each test
  before_each(function()
    config.options = nil
  end)

  describe("defaults", function()
    it("has empty connections by default", function()
      assert.are.equal(0, #config.defaults.connections)
    end)

    it("has UI configuration", function()
      assert.is_not_nil(config.defaults.ui)
      assert.is_not_nil(config.defaults.ui.grid)
    end)

    it("has keymaps configuration", function()
      assert.is_not_nil(config.defaults.keymaps)
      assert.is_not_nil(config.defaults.keymaps.open)
      assert.is_not_nil(config.defaults.keymaps.execute)
      assert.is_not_nil(config.defaults.keymaps.close)

      -- Verify new comprehensive keymaps
      assert.is_not_nil(config.defaults.keymaps.sidebar)
      assert.is_not_nil(config.defaults.keymaps.sidebar.toggle_expand)
      assert.is_not_nil(config.defaults.keymaps.sidebar.refresh)

      assert.is_not_nil(config.defaults.keymaps.history)
      assert.is_not_nil(config.defaults.keymaps.history.select)

      assert.is_not_nil(config.defaults.keymaps.editor)
      assert.is_not_nil(config.defaults.keymaps.editor.save)

      assert.is_not_nil(config.defaults.keymaps.result)
      assert.is_not_nil(config.defaults.keymaps.result.yank_row)
    end)

    it("has schema configuration", function()
      assert.is_not_nil(config.defaults.schema)
      assert.is_true(config.defaults.schema.show_system_schemas)
    end)
  end)

  describe("setup", function()
    it("merges user options with defaults", function()
      config.setup({
        connections = {
          { name = "mydb", url = "postgres://localhost/mydb" },
        },
      })

      local opts = config.get()
      assert.are.equal(1, #opts.connections)
      assert.are.equal("mydb", opts.connections[1].name)
      -- Defaults should still be present
      assert.is_not_nil(opts.ui.grid.max_width)
    end)

    it("allows overriding nested options", function()
      config.setup({
        ui = {
          grid = {
            max_width = 80,
          },
        },
      })

      local opts = config.get()
      assert.are.equal(80, opts.ui.grid.max_width)
      -- Other defaults should be preserved
      assert.is_not_nil(opts.ui.grid.max_height)
    end)

    it("works with empty options", function()
      config.setup({})
      local opts = config.get()
      assert.is_not_nil(opts)
      assert.are.equal(0, #opts.connections)
    end)

    it("works with nil options", function()
      config.setup(nil)
      local opts = config.get()
      assert.is_not_nil(opts)
    end)
  end)

  describe("get", function()
    it("returns defaults if setup not called", function()
      local opts = config.get()
      assert.is_not_nil(opts)
      assert.are.equal(0, #opts.connections)
    end)

    it("returns configured options after setup", function()
      config.setup({
        keymaps = {
          open = "<Leader>sql",
        },
      })

      local opts = config.get()
      assert.are.equal("<Leader>sql", opts.keymaps.open)
    end)

    it("returns same instance on multiple calls", function()
      config.setup({})
      local opts1 = config.get()
      local opts2 = config.get()
      assert.are.equal(opts1, opts2)
    end)
  end)
end)

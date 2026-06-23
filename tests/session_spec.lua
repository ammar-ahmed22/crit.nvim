-- Unit tests for the in-memory session state. Run with plenary:
--   nvim --headless -u tests/minimal_init.lua \
--        -c "PlenaryBustedFile tests/session_spec.lua"
local session = require("crit.session")

describe("session", function()
  before_each(function() session.detach() end)

  it("starts detached", function()
    assert.is_false(session.is_attached())
  end)

  it("loads metadata + comments via attach()", function()
    session.attach({ id = "crit-x", repo = "/r", scope = "worktree", status = "open" }, {
      comments = {
        { id = "c1", file = "a.go", side = "new", start_line = 1, end_line = 1, body = "x", kind = "comment" },
        { id = "c2", file = "a.go", side = "old", start_line = 5, end_line = 6, body = "y", kind = "nit" },
      },
    })
    assert.is_true(session.is_attached())
    assert.equals(2, #session.state.comments)
  end)

  it("filters by file and side", function()
    session.attach({ id = "crit-x" }, {
      comments = {
        { id = "c1", file = "a.go", side = "new", start_line = 1, end_line = 1 },
        { id = "c2", file = "b.go", side = "new", start_line = 1, end_line = 1 },
        { id = "c3", file = "a.go", side = "old", start_line = 1, end_line = 1 },
      },
    })
    assert.equals(1, #session.comments_for("a.go", "new"))
    assert.equals(2, #session.comments_for("a.go", nil))
    assert.equals(0, #session.comments_for("c.go", "new"))
  end)

  it("comments_at honors inclusive range", function()
    session.attach({ id = "crit-x" }, {
      comments = {
        { id = "c1", file = "a.go", side = "new", start_line = 10, end_line = 12 },
      },
    })
    assert.equals(1, #session.comments_at("a.go", "new", 10))
    assert.equals(1, #session.comments_at("a.go", "new", 11))
    assert.equals(1, #session.comments_at("a.go", "new", 12))
    assert.equals(0, #session.comments_at("a.go", "new", 13))
    assert.equals(0, #session.comments_at("a.go", "new", 9))
  end)
end)

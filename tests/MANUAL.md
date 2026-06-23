# Manual end-to-end test

The plugin needs a real diff to be meaningful; this script sets one up.

```sh
# 1. Build the crit binary so it's on $PATH.
go install github.com/ammar-ahmed22/crit@latest

# 2. Scratch repo.
mkdir /tmp/critnvim-test && cd /tmp/critnvim-test
git init -q
printf 'one\ntwo\nthree\n' > foo.txt
git add foo.txt
git -c user.email=t@t -c user.name=t commit -qm init
printf 'one\ntwo modified\nthree\nfour\n' > foo.txt

# 3. Start a session.
crit session start --title "manual e2e"
# -> note the id, e.g. crit-abc123

# 4. (Optional, validates the agent loop.) In another terminal:
#    crit session wait crit-abc123
```

In nvim (with `crit.nvim` and `diffview.nvim` installed):

1. `:CritDoctor` — expect both lines green.
2. `:CritAttach crit-abc123` — Diffview should open showing foo.txt's diff.
3. Cursor on the `+two modified` line. `:CritComment`. Type a body. `<C-s>`.
   A sign and end-of-line virt-text should appear on that line.
4. Visual-select two lines (`V` + `j`). `:'<,'>CritComment`. Type a body.
   `<C-t>` to toggle the kind to `blocking`. `<C-s>`.
5. On the first comment's line: `:CritEdit`. Change the body. `<C-s>`. The
   virt-text should update.
6. `:CritList` — quickfix opens. `<CR>` on a row jumps to the comment.
7. `:CritDelete` on the second comment's line. Confirm with `y`. The sign
   should disappear.
8. `:CritSubmit`. Press `r`. Type a summary. `<C-s>`.
9. The waiting `crit session wait` in the other terminal should now print the
   final review.json and exit 0.

Edge cases worth checking:

- Commit a change after step 3 (`git add -A && git commit -m x`). On
  reattach, the HEAD-drift warning should fire.
- Comment on a removed-only line in the left pane: the resulting comment
  should have `side: "old"` and a `-` snippet.
- Out-of-range anchor: not really exposable from the UI, but the underlying
  `crit session comment add` rejects it; check the `:CritLog` after a
  malformed manual call.

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

In nvim (with `crit.nvim` and `echasnovski/mini.diff` installed):

1. `:CritDoctor` — expect the crit binary and mini.diff lines green.
2. `:CritAttach crit-abc123` — a new tab opens: file picker on the left,
   foo.txt's inline diff (green adds, red deletes) on the right with real
   syntax highlighting. Unchanged regions far from the change are folded.
3. Cursor on the changed `two modified` line. `:CritComment`. Type a body.
   `<C-s>`. A sign and end-of-line virt-text should appear on that line.
4. Visual-select two lines (`V` + `j`). `:'<,'>CritComment`. Type a body.
   `<C-t>` to toggle the kind to `blocking`. `<C-s>`.
5. On the first comment's line: `:CritEdit`. Change the body. `<C-s>`. The
   virt-text should update.
6. `:CritList` — quickfix opens. `<CR>` on a row jumps to the comment in the
   inline diff (switching files in the picker as needed).
7. `:CritDelete` on the second comment's line. Confirm with `y`. The sign
   should disappear.
8. `:CritSubmit`. Press `r`. Type a summary. `<C-s>`.
9. The waiting `crit session wait` in the other terminal should now print the
   final review.json and exit 0.

Edge cases worth checking:

- Commit a change after step 3 (`git add -A && git commit -m x`). On
  reattach, the HEAD-drift warning should fire.
- A new file (`A` in the picker) should render as all-green; a deleted file
  (`D`) should render (its buffer is the old content, shown as removed).
- Multiple changed files: `<CR>` a different file in the picker; comments on a
  previously-opened file persist when you return to it.
- Out-of-range anchor: not really exposable from the UI, but the underlying
  `crit session comment add` rejects it; check the `:CritLog` after a
  malformed manual call.

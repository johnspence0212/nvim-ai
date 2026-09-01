# Chat look

Locked 2026-09-01 on [How should Chat look in the bottom split?](https://linear.app/johnspence/issue/JOH-67/how-should-chat-look-in-the-bottom-split), then the turn chrome on [Draw You as an empty square with a blue rail](https://linear.app/johnspence/issue/JOH-77/draw-you-as-an-empty-square-with-a-blue-rail). Visual primary source for turns: `lua/nvim_ai/prototype/chat-turns.html` variant **A** (`?variant=A`) on `johnspence0212/prototype-chat-turns`. Column layout source remains `lua/nvim_ai/prototype/chat-look.html` variant **B**. Throwaway HTML; fake stream; no ACP.

Enhance from this note rather than re-litigating the layout. Open the turn prototype in a browser (`python -m http.server` from the repo root) and flip to A.

## Locked look

- **Columns, not a bottom split.** Code is the left window. Chat is a right-hand column (~30% of the frame at first open).
- **Chat is two stacked cards** in that column: transcript above, Composer at the bottom. First open is empty. Turns stream in the transcript.
- **Square cards** with a **shared 4px stroke** (`#7aa2f7`) on the editor, transcript, and Composer. No inner border on the Composer field. Gap between cards, not a hard window rule.
- **You is an empty square** (no fill) with a **blue left rail** (`#7aa2f7`) and a `YOU` tag. Blue is You. Agent is a dump: no bubble, no rail.
- **`thinking...`** (muted) while a turn is in flight and no Agent text has arrived. It goes away on the first chunk or when the turn ends.
- **Queued** is a yellow rail and yellow `QUEUED` tag (`#e0af68`), not another You.
- **Compact solid top bar** across the whole frame: `<leader>nn` hide/show, `<leader>nc` cancel, `<leader>nk` command cheatsheet, `<C-w>>` grow, `<C-w><` shrink. Right side is a Session slot: **idle** / **in flight** / **pending**. No model name, tokens, or extras this ship.
- **Enter** sends. **Shift-Enter** inserts a newline in the Composer.
- **Hide** (`<leader>nn`) puts focus on the **code column** (last non-Chat window).
- **Grow the Chat column with Vim**, not a drag gutter: `<C-w>>` / `<C-w><` (or `:vert resize`). Same as any vsplit.
- **Command cheatsheet** (`<leader>nk`, Normal): read-only float centered on the frame, same square stroke. Chat commands only. Esc or `nk` closes it. Opens even if Chat is hidden; does not toggle Chat. Leave Insert in the Composer first. See [How does Chat show a glossary of commands?](https://linear.app/johnspence/issue/JOH-68/how-does-chat-show-a-glossary-of-commands).
- **Agent markdown** after the turn finishes (including cancel): headings, lists, emphasis, inline code, fenced code. No images, no tables. You and pending stay as typed. Streaming is plain. See [Does the Chat transcript render markdown?](https://linear.app/johnspence/issue/JOH-69/does-the-chat-transcript-render-markdown).
- **Column width** after `<C-w>>` / `<C-w><` survives `<leader>nn` hide for this Neovim process. A new Profile launch is ~30% again. See [Does the Chat column's width survive hide?](https://linear.app/johnspence/issue/JOH-70/does-the-chat-columns-width-survive-hide).

Queue behaviour is not look: see [How does Chat queue a turn while one is in flight?](https://linear.app/johnspence/issue/JOH-66/how-does-chat-queue-a-turn-while-one-is-in-flight).

## Rejected while prototyping

- Bottom ~20% full-width split (charting standing; A in the column prototype).
- REPL pad (one buffer, `>` prompt) and gutter-log + cmdline Composer.
- Equal 50/50 columns as the default (C). Width is still growable from B's sidebar.
- Drag-to-resize gutter.
- Rounded cards (first lock; replaced by square).
- Filled blue You block, right-aligned blue square (B), ASCII box-draw You (C).

## Later, without reopening the layout

Nothing further for this ship. Execution is [Ship Chat in the Profile](https://linear.app/johnspence/issue/JOH-71/ship-chat-in-the-profile).

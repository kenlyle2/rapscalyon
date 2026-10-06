# AI chat
> Keep every AI conversation per person, message by message, whichever model answered.

## Who it's for
Builders of a chat app on any model provider (LLaMA, DeepSeek, Gemini, a multi-model switcher) who want conversation storage, ordering and optional credits done safely.

## What you get
- A chat per conversation: provider, model, title and a numbered message list, owned by a workspace.
- Messages are rows, not a JSON blob: ordered, countable, capped at 5,000 per chat.
- Optionally charge core credits per reply in the same transaction; a replay never charges twice.
- Nothing is charged by default: an outside platform's credits can stay the ledger.

## Works well with
item-tracker, subject-individual, chat-with-file, chat-with-youtube.

## Under the hood
A child of item-tracker: every chat is an item (kind chat) with a 1:1 chat row and many message rows. Clients can read; only the server writes, idempotently.

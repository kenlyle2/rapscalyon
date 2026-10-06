# Chat with a video (chat-with-youtube)

Ask questions about a YouTube video from its transcript and keep the conversation per person.

Tier: official. Version 0.1.0. Chat with a video: the link, title, style, tone, transcript and summary attached 1:1 to an ai-chat conversation, with an ingestion flag. Replaces the BuilderKit chat_with_youtube table.

## Who it's for

Builders of a chat-with-a-video app who want the transcript, summary and conversation stored safely.

## What you get

- A video attached to a chat: link, title, style, tone, transcript and summary, owned by the same workspace as the chat.
- An ingestion flag that flips once the transcript is indexed.
- One video per chat; the conversation itself is an ai-chat conversation.

## Works well with

ai-chat, youtube-content, item-tracker.

## Under the hood

A 1:1 detail row on an ai-chat conversation. Clients can read; only the server writes.

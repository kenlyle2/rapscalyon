# Chat with a file (chat-with-file)

Ask questions about an uploaded document and keep the conversation per person.

Tier: official. Version 0.1.1. Chat with a document: the uploaded file's storage key and name attached 1:1 to an ai-chat conversation. Replaces the BuilderKit chat_with_file table.

## Who it's for

Builders of a chat-with-your-PDF app who want the document link and the conversation stored safely.

## What you get

- A document attached to a chat: its storage key and file name, owned by the same workspace as the chat.
- One document per chat; the conversation itself is an ai-chat conversation.
- The file is a private storage key, never an inline copy.

## Works well with

ai-chat, item-tracker, subject-individual.

## Under the hood

A 1:1 detail row on an ai-chat conversation. Clients can read; only the server writes, once.

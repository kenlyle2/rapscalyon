import os
from gen import *
class E: pass
def mk(name, title, tagline, who, gets, works, hood, desc, tables, words, extra=""):
    d = os.path.join(OUT, name)
    class P: pass
    p = P(); p.name, p.desc, p.title, p.tagline, p.who, p.gets, p.works, p.hood, p.words, p.extra_docs = name, desc, title, tagline, who, gets, works, hood, words, extra
    p.ents = []
    for t, kind, funcs in tables:
        e = E(); e.table, e.kind, e.funcs = t, kind, funcs; p.ents.append(e)
    open(os.path.join(d, "docs", "MARKETING.md"), "w").write(marketing(p))
    open(os.path.join(d, "docs", "README.md"), "w").write(docs_readme(p))
    open(os.path.join(d, "docs", "SECURITY.md"), "w").write(docs_security(p))
    print("docs", name)

mk("ai-chat", "AI chat",
   "Keep every AI conversation per person, message by message, whichever model answered.",
   "Builders of a chat app on any model provider (LLaMA, DeepSeek, Gemini, a multi-model switcher) who want conversation storage, ordering and optional credits done safely.",
   ["A chat per conversation: provider, model, title and a numbered message list, owned by a workspace.",
    "Messages are rows, not a JSON blob: ordered, countable, capped at 5,000 per chat.",
    "Optionally charge core credits per reply in the same transaction; a replay never charges twice.",
    "Nothing is charged by default: an outside platform's credits can stay the ledger."],
   "item-tracker, subject-individual, chat-with-file, chat-with-youtube",
   "A child of item-tracker: every chat is an item (kind chat) with a 1:1 chat row and many message rows. Clients can read; only the server writes, idempotently.",
   "AI chat conversations as a child of item-tracker: a chat per provider and model with its messages in order, recorded by the server, with an optional core charge per reply in the same transaction. Covers the BuilderKit llamagpt, multillm_chatgpt, deepseek_chat and gemini_chat tables with one shape.",
   [("cht_chats", "chat", ["cht_check_kind", "cht_start"]), ("cht_messages", "chat", ["cht_append"])],
   "`llamagpt`, `multillm_chatgpt`, `deepseek_chat`, `gemini_chat` (id, user_id, title, model, chat_history json): all one shape. `provider` says which app the chat came from, `title` is the item title, and each element of `chat_history` becomes a `cht_messages` row in order (role user, assistant or system).")
mk("chat-with-file", "Chat with a file",
   "Ask questions about an uploaded document and keep the conversation per person.",
   "Builders of a chat-with-your-PDF app who want the document link and the conversation stored safely.",
   ["A document attached to a chat: its storage key and file name, owned by the same workspace as the chat.",
    "One document per chat; the conversation itself is an ai-chat conversation.",
    "The file is a private storage key, never an inline copy."],
   "ai-chat, item-tracker, subject-individual",
   "A 1:1 detail row on an ai-chat conversation. Clients can read; only the server writes, once.",
   "Chat with a document: the uploaded file's storage key and name attached 1:1 to an ai-chat conversation. Replaces the BuilderKit chat_with_file table.",
   [("cwf_sources", "chat", ["cwf_attach"])],
   "`chat_with_file` (id, user_id, file, filename, chat_history): `file` becomes `file_key` (a storage key); `chat_history` lives in ai-chat's `cht_messages`.")
mk("chat-with-youtube", "Chat with a video",
   "Ask questions about a YouTube video from its transcript and keep the conversation per person.",
   "Builders of a chat-with-a-video app who want the transcript, summary and conversation stored safely.",
   ["A video attached to a chat: link, title, style, tone, transcript and summary, owned by the same workspace as the chat.",
    "An ingestion flag that flips once the transcript is indexed.",
    "One video per chat; the conversation itself is an ai-chat conversation."],
   "ai-chat, youtube-content, item-tracker",
   "A 1:1 detail row on an ai-chat conversation. Clients can read; only the server writes.",
   "Chat with a video: the link, title, style, tone, transcript and summary attached 1:1 to an ai-chat conversation, with an ingestion flag. Replaces the BuilderKit chat_with_youtube table.",
   [("cwy_sources", "chat", ["cwy_attach", "cwy_mark_ingested"])],
   "`chat_with_youtube` (id, user_id, url, video_title, style, tone, transcription, summary, ingestion_done, chat_history): the video fields move to `cwy_sources`; `chat_history` lives in ai-chat's `cht_messages`.")

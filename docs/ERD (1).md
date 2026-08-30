# Wisp — Entity Relationship Document

This is the single source of truth for database schema. Every Claude session must write code against exactly these tables/columns — do not invent new tables or rename columns. If a new table is genuinely needed, it must be added here first, in its own step, before any code references it.

## Tables

### `profiles`
Extends Supabase `auth.users`.
| Column | Type | Notes |
|---|---|---|
| id | uuid, PK | = auth.users.id |
| username | text, unique, not null | used for search/discovery |
| display_name | text | |
| avatar_url | text, nullable | Supabase Storage path |
| preferred_language | text, default 'en' | editable in settings |
| is_online | boolean, default false | updated via presence channel |
| last_seen_at | timestamptz, nullable | |
| created_at | timestamptz, default now() | |

### `conversations`
| Column | Type | Notes |
|---|---|---|
| id | uuid, PK | |
| type | text | 'direct' or 'group' |
| name | text, nullable | group name (null for direct) |
| avatar_url | text, nullable | group avatar |
| created_by | uuid, FK → profiles.id | group admin/creator |
| created_at | timestamptz, default now() | |

### `conversation_members`
| Column | Type | Notes |
|---|---|---|
| id | uuid, PK | |
| conversation_id | uuid, FK → conversations.id | |
| user_id | uuid, FK → profiles.id | |
| role | text | 'admin' or 'member'; only admin can add/remove members |
| joined_at | timestamptz, default now() | |

### `messages`
| Column | Type | Notes |
|---|---|---|
| id | uuid, PK | |
| conversation_id | uuid, FK → conversations.id | |
| sender_id | uuid, FK → profiles.id | nullable if sender is the AI agent |
| is_ai_message | boolean, default false | true when sent by embedded AI agent |
| type | text | 'text','image','video','voice','document','contact','location_current','location_live' |
| content | text, nullable | text body, or caption |
| media_url | text, nullable | Supabase Storage path for image/video/voice/document |
| original_language | text, nullable | detected language of text messages |
| translated_content | text, nullable | populated only when original_language != receiver's preferred language and != 'en' logic per PRD |
| shared_contact_id | uuid, nullable, FK → profiles.id | for 'contact' type |
| location_lat | double precision, nullable | |
| location_lng | double precision, nullable | |
| is_live_location | boolean, default false | |
| live_location_expires_at | timestamptz, nullable | |
| voice_transcript | text, nullable | AI Feature 3 output |
| voice_actions | jsonb, nullable | extracted action items, AI Feature 3 output |
| created_at | timestamptz, default now() | |

### `message_status`
Tracks delivery/read per recipient (needed for group chats where each member has independent status).
| Column | Type | Notes |
|---|---|---|
| id | uuid, PK | |
| message_id | uuid, FK → messages.id | |
| user_id | uuid, FK → profiles.id | recipient |
| status | text | 'sent','delivered','read' |
| updated_at | timestamptz, default now() | |

### `typing_status`
Ephemeral — can also be handled purely via Supabase Realtime broadcast without a table, but modeled here for clarity if persistence is wanted.
| Column | Type | Notes |
|---|---|---|
| conversation_id | uuid, FK → conversations.id | |
| user_id | uuid, FK → profiles.id | |
| is_typing | boolean | |
| updated_at | timestamptz | |

### `stories`
24-hour Status/Stories feature.
| Column | Type | Notes |
|---|---|---|
| id | uuid, PK | |
| user_id | uuid, FK → profiles.id | |
| media_url | text | image or video |
| caption | text, nullable | |
| created_at | timestamptz, default now() | |
| expires_at | timestamptz | created_at + 24h |

### `story_views`
| Column | Type | Notes |
|---|---|---|
| id | uuid, PK | |
| story_id | uuid, FK → stories.id | |
| viewer_id | uuid, FK → profiles.id | |
| viewed_at | timestamptz, default now() | |

### `calls`
| Column | Type | Notes |
|---|---|---|
| id | uuid, PK | |
| conversation_id | uuid, FK → conversations.id | |
| caller_id | uuid, FK → profiles.id | |
| type | text | 'audio' or 'video' |
| status | text | 'ringing','ongoing','ended','missed','declined' |
| started_at | timestamptz, nullable | |
| ended_at | timestamptz, nullable | |

## Relationships summary
- `profiles` 1—N `conversation_members` N—1 `conversations`
- `conversations` 1—N `messages`
- `messages` 1—N `message_status` (one row per recipient)
- `profiles` 1—N `stories` 1—N `story_views`
- `conversations` 1—N `calls`

## Realtime-specific notes
- **Watched via Supabase Realtime channels**: `messages` (new message inserts per conversation), `typing_status` (or broadcast, not persisted), `profiles.is_online` (presence), `calls` (call state changes).
- **Presence**: use Supabase Presence (not just `is_online` polling) for accurate online/offline + "who's viewing this chat" if needed later.
- **RLS (Row Level Security)**: every table must have RLS enabled. Baseline policy shape: a user can only read/write rows in conversations they are a `conversation_members` row for. `profiles` table is readable by all (for username search), writable only by the owning user.

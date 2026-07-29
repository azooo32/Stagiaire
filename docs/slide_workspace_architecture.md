# Slide Workspace Architecture

The existing Supabase schema already contains `slide_stations`, `slides`, `user_station_progress`, `user_notes`, and `user_bookmarks`, so the workspace should reuse those tables.

Recommended database change: add `metadata`, `drawing_data`, `drawing_version`, and `updated_at` to `slides`. The drawing payload is JSONB vector data:

```json
[
  {
    "id": "stroke-id",
    "tool": "pen",
    "color": 4284167925,
    "width": 2,
    "opacity": 1,
    "points": [{"x": 12, "y": 40, "pressure": 0.7}]
  }
]
```

This avoids saving drawings as images and avoids over-normalizing thousands of stroke points into separate rows. If annotations must be private per student later, use `user_notes.note_content` as JSON for a first version, or add one compact `user_slide_annotations` table only when collaboration or conflict resolution requires it.

Local storage: use Hive/Isar for production offline cache. For this app I would choose Isar when adding dependencies is acceptable because it gives indexed object storage, fast reads for recent slides, and clean sync queues. The current implementation keeps the repository boundary ready so Isar can replace the mock cache without touching the UI or drawing engine.

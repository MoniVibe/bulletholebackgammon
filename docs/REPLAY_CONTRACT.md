# Replay Contract

Every automated failure must be replayable from immutable inputs.

## Required Metadata

- `commit_sha`: Git commit used for the run.
- `workflow_run_id`: CI run ID.
- `seed`: Random seed used for the session or duel.
- `run_id`: Logical bughunt/duel run identifier.
- `trace_path`: JSONL trace path.
- `state_hash_before`: Authoritative hash before the failing action.
- `state_hash_after`: Authoritative hash after the failing action (or failure marker).

## Artifact Expectations

- Persist JSONL event traces under `artifacts/bughunt/<run_id>/...`.
- Persist a compact summary with:
  - failure type
  - ply/action index
  - current player
  - latest dice/move payload
  - winner/terminal flags
- Include enough local context to replay one session without external state.

## Replay CLI Contract

Preferred:

```bash
flutter pub run tool/replay.dart --run-id=<run_id>
```

Fallback:

```bash
flutter pub run tool/replay.dart --seed=<seed> --trace=<trace_path>
```

## Determinism Requirement

Given identical `commit_sha`, `seed`, and action trace, replay must produce the
same authoritative state hash sequence.

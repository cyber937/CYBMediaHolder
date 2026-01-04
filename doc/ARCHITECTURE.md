# Architecture — CYBMediaHolder

## Purpose

CYBMediaHolder is a backend-agnostic Swift framework that manages the
**authoritative facts of media assets**, independent from UI, Player, or Decoder.

It acts as the single source of truth for:

- Media identity
- Immutable metadata
- Analysis results
- Capability discovery

## High-level Architecture

```text
MediaHolder
├─ MediaID          (stable identity)
├─ MediaLocator     (location abstraction)
├─ MediaDescriptor  (immutable metadata)
├─ MediaStore       (mutable state, actor-isolated)
└─ Capability       (feature flags)
```

## Layered Responsibilities

| Layer      | Responsibility                     |
| ---------- | ---------------------------------- |
| Core       | Identity, metadata, invariants     |
| Services   | Probing, analysis, codec knowledge |
| Cache      | Reuse & persistence of analysis    |
| Normalized | Vendor-independent metadata layer  |

## Design Principles

- **Player-agnostic**  
  MediaHolder never knows AVPlayer, Metal, or any playback logic.

- **Immutable vs Mutable separation**

  - Descriptor: immutable facts
  - Store: mutable analysis & annotations (actor)

- **Backend abstraction**  
  Decoders/probers are abstracted via `MediaProbe`.

- **Capability-driven UI**  
  UI must branch on `Capability`, not implementation details.

## Platform Constraints

- Swift Concurrency–first design
- All public types are `Sendable`
- No global mutable state

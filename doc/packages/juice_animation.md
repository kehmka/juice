# juice_animation

> Canonical specification for the juice_animation companion package

## Purpose

Reusable animation patterns with bloc-controlled animation state.

---

## Dependencies

**External:** None

**Juice Packages:** None

---

## Architecture

### Bloc: `AnimationBloc`

**Lifecycle:** Leased (per widget)

### State

```dart
class AnimationState extends BlocState {
  final Map<String, AnimationInstance> animations;
  final bool areAnimationsEnabled;
}

class AnimationInstance {
  final AnimationStatus status;
  final double progress;
  final Duration duration;
  final Curve curve;
}
```

### Events

- `StartAnimationEvent` - Start named animation
- `StopAnimationEvent` - Stop animation
- `PauseAnimationEvent` - Pause animation
- `ResumeAnimationEvent` - Resume paused animation
- `ChainAnimationsEvent` - Sequence multiple animations

### Rebuild Groups

- `animation:{id}` - Per-animation progress
- `animation:global` - Global enable/disable

---

## Open Questions

_To be discussed_

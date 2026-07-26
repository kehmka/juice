# juice_power example

A demo with no platform underneath: `DemoPowerProvider` fakes a battery that
drains one point every two seconds **without** a status change, so what you see
moving is `PowerBloc` polling — the gap this package exists to close.

Buttons plug the imaginary cable in and out, flip the power saver, and make the
level unknown, so you can watch a consumer's gate open and close.

```bash
flutter run
```

# workspace_calendar

Demo code: a workspace calendar with agenda, week and day modes, built on the
`widgets_extended` board (the week and day grids) and synced sliver tree (the
day list), over a seeded mock calendar API. It is not part of the
`widgets_extended` library.

Run it from this directory:

```bash
flutter run
```

Check it:

```bash
flutter analyze
flutter test
```

The package depends on `widgets_extended` by path (`../..`), so it always
runs against the library in this checkout.

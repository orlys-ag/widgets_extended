# plan-implementer memory index

One line per topic, starting with its scope: `[general]`, or a module key from
the profile. Read `[general]` and your run's module. Detail lives in the
sibling file; read it on demand.

- [general] reddening 100+ assertions in one file: mutation-table harness, the five reasons a mutation fails to isolate, assertion order as a design variable - `reddening-at-scale.md`
- [board] board render and widget layers: the parent-rebuild trap that leaves cell builders stale, unused_field as a staging constraint, and the dispose-assert detach check - `board-render-widget-traps.md`
- [general] animation clock cadence in tests: the zero-elapsed first tick, binary-dividing step sizes, and why a settle-frame assertion passes for the wrong reason - `animation-clock-cadence-in-tests.md`
- [general] failure-collecting probe harness: wrapping every `expect` so one run shows every assertion a variant reddens, plus the one-line probe for a defeater variant that leaves everything green - `falsification-probe-harness.md`

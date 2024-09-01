# `profitable`

## [0.2.2] - 2024-09-01

- Improve MRR calculations with prorated churned and new MRR (hopefully fixes bad churned MRR calculations)
- Only consider paid charges for all revenue calculations (hopefully fixes bad ARPC calculations)
- Add `multiple:` parameter as another option for `estimated_valuation` (same as `at:`, just syntactic sugar)

## [0.2.1] - 2024-08-31

- Add syntactic sugar for `estimated_valuation(at: "3x")`
- Now `estimated_valuation` also supports `Numeric`-only inputs like `estimated_valuation(3)`, so that @pretzelhands can avoid writing 3 extra characters and we embrace actual syntactic sugar instead of "syntactic saccharine" (sic.)

## [0.2.0] - 2024-08-31

- Initial production ready release

## [0.1.0] - 2024-08-29

- Initial test release (not production ready)
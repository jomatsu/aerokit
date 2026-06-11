# aerokit

A monorepo of [AeroSpace](https://github.com/nikitabobko/AeroSpace) companion tools for macOS.

## Packages

| Package | Description |
| --- | --- |
| [`packages/app`](packages/app) | AeroKit — menu-bar app bundling the workspace switcher (snapshot previews) and the Exposé-style window overview |

## Development

```sh
make bootstrap  # install SwiftFormat, SwiftLint and AeroSpace through Homebrew
make format     # format all packages
make lint       # lint all packages
make build      # build all packages
make test       # test all packages
make check      # lint + build + test
```

Formatting and linting rules are shared across packages via the root `.swiftformat` and `.swiftlint.yml`.

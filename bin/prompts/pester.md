# dbatools Pester v5 Test Guide

This document used to carry its own copy of the Pester v5 standards. It was an older, shorter copy
of the same rules and had fallen behind - it was missing the instance selection guidance, the
`-Skip:` exception to the no-loose-code rule, and the discovery-time rules, and its examples still
used `$TestConfig.instance2`, which no test file uses any more.

**The test standards now live in one place: [tests/CLAUDE.md](../../tests/CLAUDE.md).**

The one section that was only here, on using here-strings for multi-line strings, has moved to
DBATOOLS STYLE REQUIREMENTS > String Formatting.

For converting a Pester v4 file, see [.github/prompts/migration.md](../../.github/prompts/migration.md).

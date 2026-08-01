# dbatools Test Style Guide

This document used to carry its own copy of the test style rules. It had drifted from the other
copies and from the tree - it forbade single quotes in a section whose own example used them, it
still showed `$TestConfig.instance2` and `$TestConfig.instance3`, which no test file uses any more,
and a find-and-replace had turned "dbatools" into "MODULE" throughout.

**The test standards now live in one place: [tests/CLAUDE.md](../../tests/CLAUDE.md).**

Everything that was only in this file has been moved there:

| Section | Now in tests/CLAUDE.md under |
|---|---|
| Comment preservation | COMMENT PRESERVATION REQUIREMENT |
| Array formatting | DBATOOLS STYLE REQUIREMENTS > Array Formatting |
| Testing for warnings | TESTING FOR WARNINGS |
| When to add or update tests, what makes a good test, balance | TEST MANAGEMENT GUIDELINES |

For converting a Pester v4 file, see [migration.md](migration.md).

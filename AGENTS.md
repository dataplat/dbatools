# Repository Agent Instructions

## Pull Request Integration

**Always squash and merge pull requests that target `development`.** Never use a
merge commit or rebase merge when integrating a PR into `development`.

Follow the PowerShell and repository conventions in `CLAUDE.md` for all other work.

## Integration Test Integrity

- A boundary is an external system such as SQL Server, S3, Azure Storage, SMTP,
  LDAP, or a file share.
- Every new or changed command behavior must have at least one behavioral or
  integration test that executes the real implementation against a separately
  running boundary on GitHub Actions or the Azure test runners. The boundary may
  be the real dependency, a production-grade compatible service, or an official
  emulator, but not an in-process fake or a purpose-built test double.
- Do not use Pester mocks, fabricated SMO objects, source/AST/text assertions, or
  call-count assertions as substitutes for behavior unless the user explicitly
  approves that exception.
- Pure unit tests may accompany that coverage, but they do not count as behavioral
  or integration coverage and must not use mocks or fakes to stand in for external
  behavior.
- Tests for S3-compatible storage must provision and use a separately running
  production-grade compatible service, such as a MinIO container, in the workflow.
- Tests for Azure Storage must provision and use the official Azurite emulator or,
  where configured, the repository's real Azure Storage credentials and runners.
- A skipped placeholder is not integration coverage. If a required dependency was
  not provisioned, the behavioral test and runner setup must fail instead of skip.
  Skipping remains appropriate when the test explicitly targets a feature that the
  tested server version does not support.

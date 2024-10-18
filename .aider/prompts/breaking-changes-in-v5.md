---
id: breaking-changes-in-v5
title: Breaking changes in v5
description: Pester v5 included an all-new runtime which lead to some breaking changes in syntax and features for existing users. See this list of breaking changes when upgrading to Pester v5
---

## Actual breaking changes

- (❗ new in 5.0.1)  The Parameters of `Invoke-Pester` changed significantly, but in 5.0.1, a compatibility parameter set was added. To allow all the v4 parameters to be used, e.g. like this `Invoke-Pester -Script $testFile -PassThru -Verbose -OutputFile $tr -OutputFormat NUnitXml -CodeCoverage "$tmp/*-*.ps1" -CodeCoverageOutputFile $cc -Show All`. The compatibility is not 100%, neither -Script not -CodeCoverage take hashtables, they just take a collection of paths. The `-Strict` parameter and `-PesterOption` are ignored. The `-Output` \ `-Show` parameter takes all the values, but translates only the most used options to Pester 5 compatible options, otherwise it uses `Detailed` output. It also allows all the Pester 5 output options, to allow you to use `Diagnostic` during migration. **This whole Legacy-parameter set is deprecated** and prints a warning when used. For more options and the Advanced interface see [simple and advanced interface](./v4-to-v5#simple-and-advanced-interface) above on how to invoke Pester.
- PowerShell 2 is no longer supported
- Legacy syntax `Should Be` (without `-`) is removed, see [Migrating from Pester v3 to v4](./v3-to-v4)
- Mocks are scoped based on their placement, not in whole `Describe` / `Context`. The count also depends on their placement. See [mock scoping](../usage/mocking#mocks-are-scoped-based-on-their-placement)
- `Assert-VerifiableMocks` was removed, see [Should -Invoke](../usage/mocking#should--invoke)
- All code placed in the body of `Describe` outside of `It`, `BeforeAll`, `BeforeEach`, `AfterAll`, `AfterEach` will run during discovery and it's state might or might not be available to the test code, see [Discovery and Run](../usage/discovery-and-run)

- `-Output` parameter has reduced options to `None`, `Normal`, `Detailed` and `Diagnostic`, `-Show` alias is removed
- `-PesterOption` switch is removed
- `-TestName` switch is replaced with `-FullNameFilter` switch
- `-Script` option was renamed to `-Path` and takes paths only, it does not take hashtables. For parametrized scripts, see [Providing external data to tests](../usage/data-driven-tests#providing-external-data-to-tests)
- Using `$MyInvocation.MyCommand.Path` to locate your script in `BeforeAll` does not work. This does not break it for your scripts and modules. Use `$PSScriptRoot` or `$PSCommandPath`. See [Migrating from Pester v4](../usage/importing-tested-functions#migrating-from-pester-v4) or the [importing ps files](https://jakubjares.com/2020/04/11/pester5-importing-ps-files/) article for detailed information.
- Should `-Throw` is using `-like` to match the exception message instead of .Contains. Use `*` or any of the other `-like` wildcard to match only part of the message.
- Variables defined during Discovery, are not available in Before*, After* and It. When generating tests via foreach blocks, make sure you pass all variables into the test using -TestCases / -ForEach.
- Gherkin is removed, and will later move to it's own module, please keep using Pester version 4.
- `TestDrive` is defined during Run only, it cannot be used in -TestCases / -ForEach.

### Deprecated features

- `Assert-MockCalled` is deprecated, it is recommended to use [Should -Invoke](../usage/mocking)
- `Assert-VerifiableMock` is deprecated, it is recommended to use [Should -InvokeVerifiable](../usage/mocking)

### Additional issues to be solved future releases

- `-Strict` switch is not available
- Inconclusive and Pending states are currently no longer available, `-Pending` and `-Inconclusive` are translated to `-Skip` both on test blocks and when using `Set-ItResult`
- Automatic Code coverage via -CI switch currently disabled as it's slow. Can still be enabled using configuration, but is largely untested.
- Generating tests using foreach during discovery time works mostly, generating them from BeforeAll, to postpone expensive work till it is needed in case the test is filtered out also works, but is hacky. Get in touch if you need it and help me refine it.
- Running on huge codebases is largely untested

**Noticed more of them? Share please!**

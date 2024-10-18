---
id: v4-to-v5
title: Migrating from Pester v4 to v5
sidebar_label: Pester v4 to v5
description: Pester v5 introduced some fundamental changes compared with Pester v4. See this guide to get help understanding and making the necessary changes to be compatible with Pester v5
---

The fundamental change in this release is that Pester now runs in two phases: Discovery and Run. During discovery, it quickly scans your test files and discovers all the Describes, Contexts, Its and other Pester blocks.

**Put all your test-code into `It`, `BeforeAll`, `BeforeEach`, `AfterAll` or `AfterEach`. Put no test-code directly into `Describe`, `Context` or on the top of your file, without wrapping it in one of these blocks, unless you have a good reason to do so.**

**All misplaced code will run during Discovery, and its results won't be available during Run. Code meant to run in Discovery should be explicitly placed into `BeforeDiscovery`, see [Data driven tests](../usage/data-driven-tests#beforediscovery).**

This will allow Pester to control when all of your code is executed, and scope it correctly. This will also keep the amount of code executed during discovery to a minimum. Keeping it fast and responsive. See [Discovery and Run](../usage/discovery-and-run) for details.


### Put setup in BeforeAll
If your test suite already puts its setups and teardowns into `Before*` and `After*`. All you need to do is move the file setup into a `BeforeAll` block:

```powershell
BeforeAll {
    # DON'T use $MyInvocation.MyCommand.Path
    . $PSCommandPath.Replace('.Tests.ps1','.ps1')
}

Describe "Get-Cactus" {
    It "Returns 🌵" {
        Get-Cactus | Should -Be '🌵'
    }
}
```

See [migration script](https://gist.github.com/nohwnd/d488bd14ab4572f92ae77e208f476ada) for a script that does it for you. Improvements are welcome, e.g. putting code between `Describe` and `It` into `BeforeAll`.

### Review your usage of Skip

Discovery also impacts `-Skip` when you use it with `-Skip:$SomeCondition`. All the code in the describe block, including your skip conditions and TestCases will be evaluated during Discovery. Prefer static global variables, or code that is cheap to executed. It is not forbidden to put code to figure out the skip outside of `BeforeAll`, but be aware that it will run on every discovery.

This won't work. `BeforeAll` runs after Discovery, and so `$isSkipped` is not defined and ends up being `$null -> $false`, so the test will run.

```powershell
Describe "d" {
    BeforeAll {
        function Get-IsSkipped {
            Start-Sleep -Second 1
            $true
        }
        $isSkipped = Get-IsSkipped
    }

    It "i" -Skip:$isSkipped {

    }
}
```

Changing the code like this will skip the test correctly, but be aware that the code will run every time Discovery is performed on that file. Depending on how you run your tests this might be every time.

```powershell
function Get-IsSkipped {
    Start-Sleep -Second 1
    $true
}
$isSkipped = Get-IsSkipped

Describe "d" {
    It "i" -Skip:$isSkipped {

    }
}
```

Consider settings the check statically into a global read-only variable (much like `$IsWindows`), or caching the response for a while. Are you in this situation? Get in touch via the channels mentioned in [Got questions?](https://github.com/pester/pester#got-questions).

### Review your usage of TestCases

`-TestCases`, much like `-Skip` are evaluated during discovery and saved for later use when the test runs. This means that doing expensive setup for them will be happening every Discovery. On the other hand, you will now find their complete content for each TestCase in `Data` on the result test object.


# New result object

The new result object is extremely rich, and used by Pester internally to make all of its decisions. Most of the information in the tree is unprocessed to allow you to to work with the raw data. You are welcome to inspect the object, and write your code based on it.

To use your current CI pipeline with the new object use `ConvertTo-Pester4Result` to convert it. To convert the new object to NUnit report use `ConvertTo-NUnitReport` or specify the `-CI` switch to enable NUnit output, code coverage and exit code on failure.


## Simple and advanced interface

`Invoke-Pester` is extremely bloated in Pester4. Some of the parameters consume hashtables that I always have to google, and some of the names don't make sense anymore. In Pester5 I aimed to simplify this interface and get rid of the hashtables. Right now I landed on two vastly different apis. With a big hole in the middle that still remains to be defined. There is the Simple interface that looks like this:

```powershell
Invoke-Pester -Path <String[]>
              -ExcludePath <String[]>
              -Tag <String[]>
              -ExcludeTag <String[]>
              -FullNameFilter <String[]>
              -Output <String>
              -CI
              -PassThru
```

And the Advanced interface that takes just Pester configuration object and nothing else:

```powershell
Invoke-Pester -Configuration <PesterConfiguration>
```

A mapping of the parameters of the simple interface to the configuration object properties on the advanced interface is:

| Parameter      | Configuration Object Property                        |
| -------------- | ---------------------------------------------------- |
| Path           | Run.Path                                             |
| ExcludePath    | Run.ExcludePath                                      |
| Tag            | Filter.Tag                                           |
| ExcludeTag     | Filter.ExcludeTag                                    |
| FullNameFilter | Filter.FullName                                      |
| Output         | Output.Verbosity                                     |
| CI             | TestResult.Enabled and Run.Exit (all set to `$true`) |
| PassThru       | Run.PassThru                                         |


## Legacy interface

The following table shows a mapping of v4 Legacy parameters (those which have not been documented under the Simple/Advanced interfaces) to the configuration object

<div className="table-wrapper">

| Parameter                      | Configuration Object Property             |
| ------------------------------ | ----------------------------------------- |
| EnableExit                     | Run.Exit                                  |
| CodeCoverage                   | CodeCoverage.Path                         |
| CodeCoverageOutputFile         | CodeCoverage.OutputPath                   |
| CodeCoverageOutputFileEncoding | CodeCoverage.OutputEncoding               |
| CodeCoverageOutputFileFormat   | CodeCoverage.OutputFormat                 |
| OutputFile                     | TestResult.OutputPath                     |
| OutputFormat                   | TestResult.OutputFormat                   |
| Show                           | Output.Verbosity (via mapping; see below) |

</div>

The following table shows the mapping for v4 *Show* property values to the configuration property *Output.Verbosity*:

| *Show* value | Configuration Object *Output Verbosity* Property |
| ------------ | ------------------------------------------------ |
| All          | Detailed                                         |
| Default      | Detailed                                         |
| Detailed     | Detailed                                         |
| Fails        | Normal                                           |
| Diagnostic   | Diagnostic                                       |
| Normal       | Normal                                           |
| Minimal      | Minimal                                          |
| None         | None                                             |


### Implicit parameters for TestCases

Test cases are super useful, but I find it a bit annoying, and error prone to define the `param` block all the time, so when invoking `It` I am defining the variables in parent scope, and also splatting them. As a result you don't have to define the `param` block:

```powershell
Describe "a" {
    It "b" -TestCases @(
        @{ Name = "Jakub"; Age = 30 }
    ) {
        $Name | Should -Be "Jakub"
    }
}
```

This also works for Mock.

#### Mocks can be debugged

Mocks don't rewrite the scriptblock you provide anymore. You can now set breakpoints into them as well as any of the ParameterFilter or Should -Invoke Parameter filter.

#### Avoid putting in InModuleScope around your Describe and It blocks

`InModuleScope` is a simple way to expose your internal module functions to be tested, but it prevents you from properly testing your published functions, does not ensure that your functions are actually published, and slows down Discovery by loading the module. Aim to avoid it altogether by using `-ModuleName` on `Mock`. Or at least avoid placing `InModuleScope` outside of `It`.

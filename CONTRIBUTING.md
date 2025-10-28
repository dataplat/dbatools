# Contributing

🥳 Welcome to the party! We are glad you are taking the first step to look at contributing to this community project.

This guide provides an overview of how the project is organized (we have a few different repos) and go over a few of the unique things with our project to help you better understand how you can contribute.

## Project Structure

As of 2023 the project has been restructured but we also have a few different repositories in play to support [dbatools](https://dbatools.io). Most of these you do not have to worry about, but so you are aware of how things are tied together.

1. [dataplat/dbatools](https://github.com/dataplat/dbatools)

    dbatools is the primary project that hosts the PowerShell codebase for the 600+ PowerShell commands in the module.

1. [dataplat/dbatools.library](https://github.com/dataplat/dbatools.library)

    As of the v2 release, the libraries for dbatools have been moved into a dedicated repository. It is also published as a dependency to the dbatools module via the PowerShell Gallery. This includes the dbatools library, SMO library, and 3rd party libaries. Contributions to dbatools module will now require this module be installed for local testing: [dbatools.library](https://powershellgallery.com/packages/dbatools.library).

1. [dataplat/appveyor-lab](https://github.com/dataplat/appveyor-lab)

    We use Appveyor for running the Pester tests for each function. We have this repository to store content that is used in our tests. This keeps the current repository clean from excess files just for testing. **Maintainers will determine if tests require files be placed in this repository**.

1. [dataplat/docs](https://github.com/dataplat/docs)

    This repository and content are auto-generated from the comment-based help (CBH) within each command for the module. Fixes and changes to the help content for a given command is addressed in the dbatools module's repository.

1. [dataplat/web](https://github.com/dataplat/web)

    This repository is were the [dbatools.io](https://dbatools.io) site content is hosted.

1. [dataplat/docker](https://github.com/dataplat/docker)

    This repository hosts the code to generate the published Docker images for the module.

## Prequisites

As noted above the `dbatools.library` is now a dependency on dbatools and therefore a dependency on any dbatools development. You can install this module via PowerShellGet or downloading from the PowerShell Gallery.

> **NOTE** The library module will be maintained by the project maintainers at this time.

## Getting Help

Our [dbatools-dev](https://aka.ms/sqlslack) Slack channel is the best avenue for asking for assistance or needing review of any work on the module. The main contributors try and stay active on this channel during the week.

We also have our [Contributors](https://github.com/dataplat/dbatools/discussions/categories/contributors) category within GitHub Discussions that can be used for discussions, clarifications, or help in getting started with our project.

## Expectations

There is always room for improvements in open-source projects from new technology becoming available to enhancements in the product(s) a project is focused on. The primary areas are listed below that we would appreciate your help on and the associated technologies you will need to have some level of experience with to work with our codebase.

> _It can be easy to get overwhelmed if you are starting out and have not worked with things like Git, GitHub, and even PowerShell. If you are reading this its a great first step 🍾. We are happy to help you get involved with our project. Please don't hesitate to use the contact methods above to reach out if you want to get involved._

### 🐛 Reports

> Experience: **Any**

This can be anything from finding bugs in our current or preview release that our tests have missed to combing through our current issues to confirm they still exist.

[Open a new issue](https://dbatools.io/new-issue/) on GitHub and fill in all the details. The title should report the affected function, followed by a brief description (e.g. _Get-DbaDatabase - Add property x to default view_). The provided template holds the details maintainers and contributors will need in order to confirm whether it is reproducible.

### 📃 Documentation

> Experience: **Beginner** (Git, Markdown, PowerShell)

Contributions in this area can help you get familiar with our commands and some of our common parameters, naming conventions, and using Git and interacting with GitHub Pull Requests (if any of this is new to you).

We strive to have all of our documentation as accurate as possible so a few areas that you can help:

- Examples: Do they actually work? Do they do what the associated description states? Are the parameters still accurate?
- Grammar: We default to [U.S. English](https://en.wikipedia.org/wiki/American_English) language in our help documentation. Are there any grammar errors?
- Anything else: fresh set of eyes on documentation can always find things we may have missed or spot checking for areas that can be improved.

### Fixing 🐛

> **NOTE** Please ensure you have an issue to work on and any discussions on the fix you will implement are done in that issue. This helps keep the background on the change in one place and removes any guesswork.

We have a [step-by-step guide](https://dbatools.io/firstpull) if you're new to Github or need a refresh.

[Open a PR](https://github.com/dataplat/dbatools/pulls) targeting ideally just one ps1 file (the PR needs to target the _development_ branch), with the name of the function being fixed as a title. Everyone will chime in reviewing the code and either approve the PR or request changes. The more targeted and focused the PR, the easier to merge, the fastest to go into the next release. Keep them as simple as possible to speed up the process.

### 👩‍💻 New Commands

> **NOTE** Any new command must have maintainer approval via a feature issue prior to submitting a pull request.

Start out reviewing the [list of functions and documentation](https://docs.dbatools.io), or pulling the list from the module. Our module is over 600+ commands currently, we prefer at this stage to enhance our current commands unless there is justification for a new command. If you find something similar already exists, open [a new issue on GitHub](https://github.com/dataplat/dbatools/issues/new) to request an enhancement to that command. New ideas already accepted can be found on [Feature](https://github.com/dataplat/dbatools/labels/Feature) tagged issues. If nothing similar pops up, you can start a new issue for discussion or ping us in contact methods noted above with the details or requirements you need. (_GitHub issue is preferred to just have the history around._)

## Standards

Our project follows most of the same [standards the PowerShell Team promotes](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines). A few of the primary things we require as standards are listed below as well.

### Parameter Standards

1. PascalCasing (e.g. `$SqlInstance`, `$ExcludeLogin`)
1. Singular (always)

### Variable Standards

1. No use of single letter variables (e.g., `$i`)
1. Variable name should be readable and self-explanatory, but does not have to be an essay style (e.g., good: `$loginDestServer` not: `$dbLoginForDestinationServer`)
1. Use camelCase for multiple word variables (e.g., `$currentLogin`, `$dbLogin`)
1. Foreach loops should use plural collections and singular variable in the loop (e.g., `foreach ($db in $databases) {...}` or `foreach ($db in $dbs) {...}`)

[This page](https://github.com/dataplat/dbatools/wiki/Standard-Documentation) sums up what we currently use. We aim at standardizing and reducing to a set of self-documenting and reusable variables.

### Formatting and indentation

We 💘 OTBS with this project. Contributors will find an easier experience with our formatting standards using [Visual Studio Code](https://aka.ms/vscode). If for some reason your instance of VS Code is not formatting the PowerShell file you can leveraging `Invoke-DbatoolsFormatter` which does the groundwork for you.

**We do have a Pester test that will validate the format of the file in any Pull Request.**

## Pester 🧪

Our project uses [Pester](https://pester.dev) for our testing framework. Appveyor runs a matrix of environments that test against various versions of SQL Server. We do have some commands that cannot be tested easily but the majority we use Pester to ensure the code behaves properly. Appveyor runs these tests for each-and-every commit in our repository.

We strive to have the Pester tests where any user can pull the project and run the same test in their environment (on a test lab of course or in our Docker image).

### Standard

- Tests name should following standard: `<command-name>.Tests.ps1` (e.g., `Get-DbaDatabase.Tests.ps1`)
- Prefix all created resources with `dbatoolsci_`
- If multiple resources are to be created add a random number to the prefix to ensure it is unique (e.g., `dbatoolsci_user_$(Get-Random)`)
- Any tests creating resource should always cleanup via `AfterAll` or `AfterEach` blocks
- Each test should have two primary Describe blocks and be tagged accordingly: UnitTests and IntegrationTests
  - `Describe "$CommandName Unit Tests" -Tag 'UnitTests' {...}`
  - `Describe "$commandname Integration Tests" -Tag "IntegrationTests" {...}`

Tests make sure a "contract" is made between the code and its behavior: once a test is formalized, changes to the code itself or enhancement will be written making sure existing functionality is retained, making the entire dbatools experience more stable.

You can inspect/copy/cannibalize existing tests. You'll see that every test file is named with a simple convention `Verb-Noun*.Tests.ps1`, and this is required by [Pester](https://GitHub.com/pester/Pester), which is the de-facto standard for running tests in PowerShell.

## AppVeyor Environment

AppVeyor is hooked up to test any commit, including PRs. Each commit triggers 5 builds, each referred to as a "scenario". We have the scenarios setup where the dbatools log is published as an artifact should you need to view why test are failing.

- 2008R2 : a server with a single SQL Server 2008 R2 Express Edition instance available ($script:instance1)
- 2016 : a server with a single SQL Server 2016 Developer Edition instance available ($script:instance2)
- 2016_service: used to test service restarts
- 2016_2017 : a server with two instances available, 2016 and 2017 Developer Edition
- default: a server with two instances available, one SQL Server 2008 R2 Express Edition and a SQL Server 2016 Developer Edition

Builds are split among "scenario"(s) because not every test requires everything to be up and running, and resources on AppVeyor are constrained.

Ideally:

1. Whenever possible, write UnitTests.
2. You should write IntegrationTests ideally running in **EITHER** the 2008R2 or the 2016 "scenario".
3. Default and 2016_2017 are the most resource constrained and are left to run the Copy-* commands which are the only ones **needing** two active instances.
4. If you want to write tests that, e.g, target **BOTH** 2008R2 and 2016, try to avoid writing tests that need both instances to be active at the same time.

AppVeyor is set up to recognize what "scenario" is required by your test, simply inspecting for the presence of combinations of `$script:instance1`, `$script:instance2` and `$script:instance3`. If you need to fall into case (4), write two test files, e.g. _Get-DbaFoo.first.Tests.ps1_ (targeting `$script:instance1` only) and _Get-DbaFoo.second.Tests.ps1_ (targeting `$script:instance2` only).

Most PRs will target `public/*.ps1` files to add functionality or resolve bugs.
Our test runner will try and figure out what tests needs to be run based on the files modified in the PR, plus all the dependencies.

If the automatic detection doesn't work, and you don't want to wait for the entire test suite to run (i.e. you need to run only `Get-DbaFoo` on AppVeyor), you can use a **_magic command_** within the commit message, namely `(do Get-DbaFoo)` . This will run only test files within the test folder matching this mask `tests\*Get-DbaFoo*.Tests.ps1`.

<!-- TODO: how to run your own AppVeyor before pushing a PR -->

## Codecov

We utilize Codecov as many other PowerShell community projects are doing. You can see those coverage reports directly on Codecov site for our project.

[Codecov - dataplat/dbatools](https://app.codecov.io/gh/dataplat/dbatools/tree/development)

This system allows us to see the percentage of the coverage for our tests. A rough goal is getting as close to 80% coverage, some commands we have that are just not achievable due to various limitations. As part of our test framework that runs on Appveyor we upload a coverage file to Codecov so it stays current.

If you want to start contributing new tests, choose the ones with no coverage. You can also inspect functions with low coverage and improve existing tests. [See improving test](https://dbatools.io/improving-tests/).

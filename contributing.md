Here, we'll help you understand how to contribute to the project, and talk about fun stuff like styles and guidelines.

# Contributing

Let's sum this up saying that we'd love your help. There are several ways to contribute:

- Create new commands (PowerShell/T-SQL knowledge required)
- Report bugs (everyone can do it)
- Tests (Pester knowledge required)
- Documentation: functions, website, this guide, everything can be improved (everyone can)
- Code review (PowerShell/T-SQL knowledge required)

Our [dbatools-dev](https://sqlcommunity.slack.com/messages/C3EJ852JD/) Slack channel is best avenue for asking for assistance or needing review of any work on the module. The main contributors stay active on this channel during the week for the most part.

## Documentation

Documentation is an area that is a good starting point whether you are new to open-source projects and/or git and GitHub. The documentation focus is around our comment-based help (CBH) that is what drives the new documentation site we have: [docs.dbatools.io](https://docs.dbatools.io). The CBH is included with every public command (and some internal), and is the content you see using `Get-Help Function-Name`. Reviewing the content to ensure it is clear on what the command is used for, along with working examples is a key area of discussion. Whether you are first starting out with PowerShell or have been using it for years, your fresh eyes can help spot inaccuracies or areas of improvement on how we document each command. If anything is found you can raise an issue to bring it to our attention, then work on a pull request to address it once approved.

## Contributing New Commands

Start out reviewing the [list of functions and documentation](https://docs.dbatools.io), or pulling the list from the module with `Get-Command -Module dbatools -CommandType Function | Out-GridView`. If you find something similar already exists, open [a new issue on GitHub](https://GitHub.com/sqlcollaborative/dbatools/issues/new) to request an enhancement to that command. New ideas already accepted can be found on [Feature](https://github.com/sqlcollaborative/dbatools/labels/Feature) tagged issues. If nothing similar pops up, you can start a new issue for discussion or ping us in Slack with the details or requirements you need. (_GitHub issue is preferred to just have the history around._)

## Reporting Bugs

[Open a new issue](https://dbatools.io/new-issue/) on GitHub and fill in all the details. The title should report the affected function, followed by a brief description (e.g. _Get-DbaDatabase - Add property x to default view_). The provided template holds most of the details we need in order to confirm whether it is reproducible and a potential fix.

## Fix Bugs

We have a [step-by-step guide](https://dbatools.io/firstpull) if you don't know Github enough.
[Open a PR](https://GitHub.com/sqlcollaborative/dbatools/pulls) targeting ideally just one ps1 file (the PR needs to target the *development* branch), with the name of the function being fixed as a title. Everyone will chime in reviewing the code and either approve the PR or request changes. The more targeted and focused the PR, the easier to merge, the fastest to go into the next release. Keep them as simple as possible to speed up the process.

## Parameters and Variables

As a reference: when we refer to [parameters](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parameters) these at the command level for accepting input; used when calling a given command like `Get-DbaDatabase -SqlInstance MyServer` (`SqlInstance` is the parameter). A [variable](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_variables) is used within a given command to store values or objects that are used in the given command's code.

We chose to follow the standards below when creating parameters and variables for a function:

1) Any variable used in the parameter block must have first letter of each word capitalized. (e.g. `$SqlInstance`, `$ExcludeLogin`)
1) Any variable used in the parameter block **is required** to be singular.
1) Any variable not part of the parameter block, that is multiple words, will follow the camelCase format. (e.g. `$currentLogin`, `$dbLogin`)
1) Refrain from using single character variable names (e.g. `$i` or `$x`). Try to make them "readable" in the sense that if someone sees the variable name they can get a hint what it presents (e.g. `$db`, `$operatorName`).

When you are working with "objects" in SQL Server, say with databases, what variable name you use should be based on what operation you are doing. You can find examples of various situations in the current code of the module to see more detailed examples. As an example: in situations where you are looping over the databases for an instance, try to use a plural variable name for the collection and then single or abbreviated name in the loop for each object of that collection. e.g. `foreach ($db in $databases) {...`.

[This page](https://github.com/sqlcollaborative/dbatools/wiki/Standard-Documentation) sums up what we currently use. We aim at standardizing and reducing to a set of self-documenting and reusable parameters. If you have any questions around the above do not hesitate to ask in Slack.

## Formatting and indentation

We favour consistency throughout the project and accept PRs coming from anybody. Just know that you can reformat your new function leveraging Invoke-DbaFormatter which does the groundwork for you.

## Tests

Remember that tests are needed to make sure dbatools code behaves properly. The ultimate goal is for any user to be able to run dbatools' tests within their environment and, depending on the result, be sure everything works as expected. Dbatools works on a matrix of environments that will hardly be fully covered by a Continuous Integration system. That being said, we have AppVeyor (see later) set up to run at each and every commit.

### How to write tests

To save resources and be more flexible, we split tests with tags into two main categories, `UnitTests` and `IntegrationTests`. Below is a starting list of things to consider when writing your test:

- `UnitTests` do not require an instance to be up and running, and are easily the most flexible to be ran on every user computer. - `IntegrationTests` instead require one or more active instances, and there is a bit of setup to do in order to run them.
- Every one of the `IntegrationTests` may need to create a resource (e.g. a database).
- Every resource should be named with the `dbatoolsci_` prefix. _The test should attempt to clean up after itself leaving a pristine environment._
- Try to write tests thinking they may run in each and every user's test environment.

The [dbatools-templates repository](https://github.com/sqlcollaborative/dbatools-templates) holds examples, but you can also inspect/copy/cannibalize existing tests. You'll see that every test file is named with a simple convention `Verb-Noun*.Tests.ps1`, and this is required by [Pester](https://GitHub.com/pester/Pester), which is the de-facto standard for running tests in PowerShell.

Tests make sure a "contract" is made between the code and its behavior: once a test is formalized, changes to the code itself or enhancement will be written making sure existing functionality is retained, making the entire dbatools experience more stable.

### TODO: how to run tests in your environment, tests\manual.pester.ps1

### AppVeyor setup

AppVeyor is hooked up to test any commit, including PRs. Each commit triggers 5 builds, each referred to as a "scenario". We have the scenarios setup where the dbatools log is published as an artifact should you need to view why test are failing.

- 2008R2 : a server with a single SQL Server 2008 R2 Express Edition instance available ($script:instance1)
- 2016 : a server with a single SQL Server 2016 Developer Edition instance available ($script:instance2)
- 2016_service: used to test service restarts
- 2016_2017 : a server with two instances available, 2016 and 2017 Developer Edition
- default: a server with two instances available, one SQL Server 2008 R2 Express Edition and a SQL Server 2016 Developer Edition

Builds are split among "scenario"(s) because not every test requires everything to be up and running, and resources on AppVeyor are constrained.

Ideally:

1) Whenever possible, write UnitTests.
1) You should write IntegrationTests ideally running in **EITHER** the 2008R2 or the 2016 "scenario".
1) Default and 216_2017 are the most resource constrained and are left to run the Copy-* commands which are the only ones **needing** two active instances.
1) If you want to write tests that, e.g, target **BOTH** 2008R2 and 2016, try to avoid writing tests that need both instances to be active at the same time.

AppVeyor is set up to recognize what "scenario" is required by your test, simply inspecting for the presence of combinations of `$script:instance1`, `$script:instance2` and `$script:instance3`. If you need to fall into case (4), write two test files, e.g. _Get-DbaFoo.first.Tests.ps1_ (targeting `$script:instance1` only) and _Get-DbaFoo.second.Tests.ps1_ (targeting `$script:instance2` only).

If you don't want to wait for the entire test suite to run (i.e. you need to run only `Get-DbaFoo` on AppVeyor), you can use a **_magic command_** within the commit message, namely `(do Get-DbaFoo)` . This will run only test files within the test folder matching this mask `tests\*Get-DbaFoo*.Tests.ps1`.

###TODO: how to run your own AppVeyor before pushing a PR

### Code Coverage, AKA improving tests

A recent introduction in our CI pipeline is code coverage. [Dbatools' CodeCov](https://codecov.io/gh/sqlcollaborative/dbatools/branch/development) shows the percentage of the coverage. Each commit on GitHub triggers a build on AppVeyor. Every build on AppVeyor triggers a code coverage calculation, which is reported to `codecov.io` for public consumption. The more code covered the more stable the code will be. Once it reaches 100%, you can be pretty sure there will be zero surprises when you use the command.

If you want to start contributing new tests, choose the ones with no coverage. You can also inspect functions with low coverage and improve existing tests. [See improving test](https://dbatools.io/improving-tests/).

## Bill of Health

In order to the highest perfection possible in everything discussed above we have setup a **Bill of Health** on each public command. [See Bill of Health](https://sqlcollaborative.github.io/boh).

As commands expand in functionality and new commands are added the health can change on any given commit. As of right now we use this as reference to reach major release status (e.g. 1.0) for the module. We may continue to expand on the checks for later releases.

There are a few checks which need a core developer to manually sign off the "check", but there are a lot everyone else can fix too, namely ScriptAnalyzer and CodeCoverage.

Here, we'll help you understand how to contribute to the project, and talk about fun stuff like styles and guidelines.

# Contributing
Let's sum this up saying that we'd love your help. We're slowly getting ready for the 1.0 release albeit a bit too slowly!

There are several ways to contribute:
 - Create new commands (PowerShell/T-SQL knowledge required)
 - Report bugs (everyone can do it)
 - Tests (Pester knowledge required)
 - Documentation: functions, website, this guide, everything can be improved (everyone can)
 - Code review (PowerShell/T-SQL knowledge required)

If you wanna help reaching 1.0
   - Standardize param names (@wsmelton)
   - Create tests for existing functions (@cl and @niphlod)
   - Review existing function documentation (@alevyinroc or @gbargsley)
   - Prepare for 1.0 with "code style" (Bill of Health, more on that later)

We strive to make any area doubtless. In any case, the Slack channel is pretty active and every area has one (or more) volunteers to refer to in case of doubts.

## Documentation
Documentation is really the area we welcome any help possible. The documentation refers to both the CBH (Comment Based Help) and the [website documentation](https://dbatools.io/functions). The CBH documentation is included with each command and is the content you see when you run `Get-Help Function-Name`. If any of that content is not clear enough or if the examples in the functions are not working, you should say so (e.g. raise an issue on GitHub or comment in Slack). Even if you are a casual user or a PowerShell newbie, we need your angle to make it as straight forward and clear as possible.

## Contribute New Commands
Start out reviewing the [list of functions on the website](https://dbatools.io/functions/), or pulling the list from the module with `Get-Command -Module dbatools -CommandType Function | Out-GridView`. If you find something similar already exists, open [a new issue on GitHub](https://GitHub.com/sqlcollaborative/dbatools/issues/new) to request an enhancement to that command. New ideas already accepted can be found on [New Command](https://github.com/sqlcollaborative/dbatools/labels/Type%3A%20New%20Command) tagged issues. If nothing similar pops up, either ping @cl on Slack with your idea about the new command or open a new issue on GitHub with details or requirements you need.

## Report Bugs
[Open a new issue](https://GitHub.com/sqlcollaborative/dbatools/issues/new) on GitHub and fill in all the details. The title should report the affected function, followed by a brief description (e.g. _Get-DbaDatabase - Add property x to default view_). The provided template holds most of the details coders need to fix the issue.

## Fix Bugs
If you don't know to use github, we have a [step-by-step guide](https://dbatools.io/firstpull) to get acquainted.
[Open a PR](https://GitHub.com/sqlcollaborative/dbatools/pulls) targeting ideally just one ps1 file (the PR needs to target the *development* branch), with the name of the function being fixed as a title. Everyone will chime in reviewing the code and either approve the PR or request changes. The more targeted and focused the PR, the easier to merge, the fastest to go into the next release. Keep them as simple as possible to speed up the process.

## Standardize Parameters and Variables
As a reference: when we refer to parameters these are the `$SqlInstance` type variables within the `param()` block that allow a function to accept input. A variable will be any `$whateverName` used within a function's code.

We chose to follow the standards below when creating parameters and variables for a function:

1) Any variable used in the parameter block must have first letter of each word capitalized. (e.g. `$SqlInstance`, `$ExcludeLogin`)
2) Any variable used in the parameter block **is required** to be singular.
3) Any variable not part of the parameter block, that is multiple words, will follow the camelCase format. (e.g. `$currentLogin`, `$dbLogin`)
4) Refrain from using single character variable names (e.g. `$i` or `$x`). Try to make them "readable" in the sense that if someone sees the variable name they can get a hint what it presents (e.g. `$db`, `$operatorName`).

When you are working with "objects" in SQL Server, say with databases, what variable name you use should be based on what operation you are doing. You can find examples of various situations in the current code of the module to see more detailed examples. As an example: in situations where you are looping over the databases for an instance, try to use a plural variable name for the collection and then single or abbreviated name in the loop for each object of that collection. e.g. `foreach ($db in $databases) {...`.

If you have any questions around the above do not hesitate to ask in Slack.

## Tests
Remember that tests are needed to make sure dbatools code behaves properly. The ultimate goal is for any user to be able to run dbatools' tests within their environment and, depending on the result, be sure everything works as expected. Dbatools works on a matrix of environments that will hardly be fully covered by a Continuous Integration system. That being said, we have AppVeyor (see later) set up to run at each and every commit.

### How to write tests
To save resources and be more flexible, we split tests with tags into two main categories, "UnitTests" and "IntegrationTests". Below is a starting list of things to consider when writing your test:
- "UnitTests" do not require an instance to be up and running, and are easily the most flexible to be ran on every user computer. - "IntegrationTests" instead require one or more active instances, and there is a bit of setup to do in order to run them.
- Every one of the "IntegrationTests" may need to create a resource (e.g. a database).
- Every resource should be named with the "dbatoolsci_" prefix. _The test should attempt to clean up after itself leaving a pristine environment._
- Try to write tests thinking they may run in each and every user's test environment.

The dbatools-templates repository holds examples, but you can also inspect/copy/cannibalize existing tests. You'll see that every test file is named with a simple convention _Verb-Noun*.Tests.ps1_, and this is required by [Pester](https://GitHub.com/pester/Pester), which is the de-facto standard for running tests in PowerShell.

Tests make sure a "contract" is made between the code and its behavior: once a test is formalized, changes to the code itself or enhancement will be written making sure existing functionality is retained, making the entire dbatools experience more stable.

TODO: how to run tests in your environment, tests\manual.pester.ps1

### AppVeyor setup

AppVeyor is hooked up to test any commit, including PRs. Each commit triggers 4 builds, each referred to as a "scenario":
 - 2008R2 : a server with a single SQL Server 2008 R2 Express Edition instance available ($script:instance1)
 - 2016 : a server with a single SQL Server 2016 Developer Edition instance available ($script:instance2)
 - 2016_service: used to test service restarts
 - default: a server with two instances available, one SQL Server 2008 R2 Express Edition and a SQL Server 2016 Developer Edition

Builds are split among "scenario"(s) because not every test requires everything to be up and running, and resources on AppVeyor are constrained.

Ideally:
 1) Whenever possible, write UnitTests.
 2) You should write IntegrationTests ideally running in **EITHER** the 2008R2 or the 2016 "scenario".
 3) Default is the most resource constrained and is left to run the Copy-* commands; which are the only ones **needing** two active instances.
 4) If you want to write tests that target **BOTH** 2008R2 and 2016, try to avoid writing tests that need both instances to be active at the same time.

AppVeyor is set up to recognize what "scenario" is required by your test, simply inspecting for the presence of "$script:instance1" and/or "$script:instance2". If you need to fall into case (4), write two test files, e.g. _Get-DbaFoo.first.Tests.ps1 (targeting $script:instance1 only) and _Get-DbaFoo.second.Tests.ps1_ (targeting $script:instance2 only). If you don't want to wait for the entire test suite to run (i.e. you need to run only Get-DbaFoo on AppVeyor), you can use a "magic command" within the commit message, namely `(do Get-DbaFoo)` . This will run only test files within the test folder matching this mask `tests\*Get-DbaFoo*.Tests.ps1`.

TODO: how to run your own AppVeyor before pushing a PR

### Code Coverage, AKA improving tests
A recent introduction in our CI pipeline is code coverage. [Dbatools' CodeCov](https://codecov.io/gh/sqlcollaborative/dbatools/branch/development) shows the percentage of the coverage. Each commit on GitHub triggers a build on AppVeyor. Every build on AppVeyor triggers a code coverage calculation, which is reported to codecov.io for public consumption. The more code covered the more stable the code will be. Once it reaches 100%, you can be pretty sure there will be zero surprises when you'll use the command.

If you want to start contributing new tests, choose the ones with no coverage. You can also inspect functions with low coverage and improve existing tests (https://dbatools.io/improving-tests/)


## Bill of Health

In order to reach 1.0, on top of everything discussed above, we choose to wait for each and every command to adhere to a fixed set of standards. Given most of those "checks" are on a function-by-function basis (with one or more activities tied to each "check"), we came up with the "Bill of Health". You can find it bill at [sqlcollaborative.github.io/boh](https://sqlcollaborative.github.io/boh).

When each and every function is healthy enough, the module itself will be ready for 1.0 release. We may continue to use the same approach (with different checks) for later releases.

There are a few checks which need a core developer to manually sign off the "check", but there are a lot everyone else can fix too, namely ScriptAnalyzer and CodeCoverage.



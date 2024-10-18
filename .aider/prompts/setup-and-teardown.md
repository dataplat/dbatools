---
title: Setup and teardown
description: Pester offers multiple ways to run code before, and after your tests to set them up, and clean up after them
---

### Setup and teardown

Pester offers multiple ways to run code before, and after your tests to set them up, and clean up after them. The setup is represented by a `BeforeAll`, and `BeforeEach` blocks.

The teardown is used to clean up after test or a block and is guaranteed to run even if the test fails. Teardown is represented by `AfterAll` and `AfterEach` blocks.

### BeforeAll

`BeforeAll` is used to share setup among all the tests in a `Describe / Context` including all child blocks and tests. `BeforeAll` runs during `Run` phase and runs only once in the current block.


The typical usage is to setup the whole test script, most commonly to import the tested function, by dot-sourcing the script file that contains it:

```powershell
BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1','.ps1')
}

Describe "API validation" {
    # ...
}
```

Another typical usage is to do an expensive operation once, and then validate the result in multiple tests:

```powershell
Describe "API validation" {
    BeforeAll {
        # this calls REST API and takes roughly 1 second
        $response = Get-Pokemon -Name Pikachu
    }

    It "response has Name = 'Pikachu'" {
        $response.Name | Should -Be 'Pikachu'
    }

    It "response has Type = 'electric'" {
        $response.Type | Should -Be 'electric'
    }
}
```

### BeforeEach

`BeforeEach` runs once before every test in the current or any child blocks. Typically this is used to create all the prerequisites for the current test, such as writing content to a file. For example this is how we ensure that each test gets fresh file:

```powershell
Describe "File parsing" {
    BeforeEach {
        # randomized path, to get fresh file for each test
        $path = "$([IO.Path]::GetTempPath())/$([Guid]::NewGuid())_form.xml"
        Copy-Item -Source $template -Destination $path -Force | Out-Null
    }

    It "Writes username" {
        Write-XmlForm -Path $file -Field "username" -Value "nohwnd"
        $content = Get-Content $file
        # ...
    }

    It "Writes name" {
        Write-XmlForm -Path $file -Field "name" -Value "Jakub"
        $content = Get-Content $file
        # ...
    }
}
```


### AfterEach

`AfterEach` runs once after every test in the current or any child blocks. Typically this is used to clean up resources created by the test, or its setups. `AfterEach` runs in a finally block, and is guaranteed to run even if the test (or setup) fails. For example this is how we ensure that each test removes its test file:

```powershell
Describe "File parsing" {
    BeforeEach {
        # randomized path, to get fresh file for each test
        $path = "$([IO.Path]::GetTempPath())/$([Guid]::NewGuid())_form.xml"
        Copy-Item -Source $template -Destination $path -Force | Out-Null
    }

    It "Writes username" {
        Write-XmlForm -Path $file -Field "username" -Value "nohwnd"
        $content = Get-Content $file
        # ...
    }

    It "Writes name" {
        Write-XmlForm -Path $file -Field "name" -Value "Jakub"
        $content = Get-Content $file
        # ...
    }

    AfterEach {
        if (Test-Path $file) {
            Remove-Item $file -Force
        }
    }
}
```

`AfterEach` placement within the current block does not affect when it is run, you can place it on the top or on the bottom of the block, and it will still run last.

The teardown in `AfterEach` should be prepared to run at any place of `BeforeEach` or `It`. For example when the `$file` does not exist yet, because we got `AccessDenied` when trying to write it.

### AfterAll

`AfterAll` runs once after every `Describe` or `Context` block. It is used to clean up common resources. It works the same as `AfterEach`, except that it just runs once.

### Multiple setups and teardowns

When multiple `BeforeAll` are defined, they run in the order in which they were defined. `AfterAll` run in the opposite order.

When multiple `BeforeEach` are defined, they run in the order in which they were defined, and they run right before the test they setup. `AfterEach` run right after the test is finished, in the opposite order.

There can be only one setup or teardown of each kind in a block.

```powershell
BeforeAll {
    Write-Host "-> Top-level BeforeAll"
}

Describe "d" {
    BeforeAll {
        Write-Host "-> Describe BeforeAll"
    }

    BeforeEach {
        Write-Host "-> Describe BeforeEach"
    }

    Context "Whitespace" {
        BeforeAll {
            Write-Host "-> Context BeforeAll"
        }

        BeforeEach {
            Write-Host "-> Context BeforeEach"
        }

        It "i" {
            # ...
        }

        AfterEach {
            Write-Host "-> Context AfterEach"
        }

        AfterAll {
            Write-Host "-> Context AfterAll"
        }
    }

    AfterEach {
        Write-Host "-> Describe AfterEach"
    }

    AfterAll {
        Write-Host "-> Describe AfterAll"
    }
}

AfterAll {
    Write-Host "-> Top-level AfterAll"
}
```
```
Running tests from 'xxx'
-> Top-level BeforeAll
-> Describe BeforeAll
-> Context BeforeAll
Describing d
 Context Whitespace
-> Describe BeforeEach
-> Context BeforeEach
-> Context AfterEach
-> Describe AfterEach
   [+] i 89ms (86ms|4ms)
-> Context AfterAll
-> Describe AfterAll
-> Top-level AfterAll
Tests completed in 543ms
Tests Passed: 1, Failed: 0, Skipped: 0 NotRun: 0
```


### Skipping setups and teardowns

Setups and teardowns are skipped when the current tree won't result in any test being run. In the example below, running Pester with the `-ExcludeTag Acceptance` filter will exclude all tests in the Describe-block. As a result the associated setup and teardown blocks will also be skipped.

```powershell
BeforeAll {
    Start-Sleep -Seconds 3
}

Describe "describe 1" {
    BeforeAll {
        Start-Sleep -Seconds 3
    }

    It "acceptance test 1" -Tag "Acceptance" {
        1 | Should -Be 1
    }

    AfterAll {
        Start-Sleep -Seconds 3
    }
}
```

```
Starting test discovery in 1 files.
Found 1 tests. 64ms
Test discovery finished. 158ms
Tests completed in 139ms
Tests Passed: 0, Failed: 0, Skipped: 0, Total: 1, NotRun: 1
```

### Scoping

All variables defined in `BeforeAll` are available to all child blocks and tests. But because all child blocks and tests run in their own scopes, the variables are not writeable to them. This is needed to isolate tests from each other.

```powershell
Describe "d" {
    BeforeAll {
        $a = "BeforeAll"
    }
    It "Write a" {
        $a = "Test"
    }

    It "Check a" {
        $a | Should -Be "BeforeAll"
    }

    AfterAll {
        Write-Host "-> AfterAll"
    }
}
```
```
Describing d
  [+] Write a 7ms (1ms|6ms)
  [+] Check a 4ms (3ms|1ms)
-> AfterAll
Tests completed in 347ms
```

`BeforeEach`, `It` and `AfterEach` run in the same scope. All variables in them are shared. This way you can move code between `BeforeEach` and `It` without changes. And you can also base your `AfterEach` on variables that were defined in `It`, for example to delete a file you created in it.

```powershell
Describe "d" {
    It "Write a" {
        $a = "Test"
    }

    AfterEach {
        Write-Host "-> $a"
    }
}
```

```
Describing d
-> Test
  [+] Write a 7ms (3ms|4ms)
Tests completed in 227ms
```

# Testing Best Practices Directive

## PARAMETER VALIDATION TESTS

Implement parameter validation tests using this exact pattern without deviation.

Filter out WhatIf/Confirm parameters using the specified approach:

```powershell
Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
```

## INTEGRATION TEST STRUCTURE

Implement integration tests following this exact pattern:

```powershell
Describe $CommandName -Tag IntegrationTests {
    Context "When connecting to SQL Server" {
        BeforeAll {
            $allResults = @()
            foreach ($instance in $TestConfig.Instances) {
                $allResults += Get-DbaDatabase -SqlInstance $instance
            }
        }

        It "Returns database objects with required properties" {
            $allResults | Should -BeOfType Microsoft.SqlServer.Management.Smo.Database
            $allResults[0].Name | Should -Not -BeNullOrEmpty
        }

        It "Always includes system databases" {
            $systemDbs = $allResults | Where-Object Name -in "master", "model", "msdb", "tempdb"
            $systemDbs.Count | Should -BeExactly 4
        }
    }
}
```

## TEMPORARY RESOURCE MANAGEMENT

Replace all temporary file/directory creation with unique names using Get-Random pattern.

Add cleanup code with -ErrorAction SilentlyContinue to all AfterAll or AfterEach blocks:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Create unique temp path for this test run
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory
    }

    AfterAll {
        # Always clean up temp files
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
    }

    Context "When performing backups" {
        # test code here
    }
}
```
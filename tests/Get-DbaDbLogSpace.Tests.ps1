#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbLogSpace",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "ExcludeSystemDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test Get-DbaDbLogSpace, we need a database with a specific log file size configuration.

        # Set variables. They are available in all the It blocks.
        $db1 = "dbatoolsci_$(Get-Random)"
        $dbCreate = "CREATE DATABASE [$db1]
        GO
        ALTER DATABASE [$db1] MODIFY FILE ( NAME = N'$($db1)_log', SIZE = 10MB )"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $dbCreate

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbLogSpace -SqlInstance $TestConfig.InstanceSingle -Database $db1
        }

        It "Should have correct properties" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have database name of $db1" {
            $results.Database | Should -Contain $db1
        }

        It "Should show correct log file size for $db1" {
            ($results | Where-Object Database -eq $db1).LogSize.Kilobyte | Should -BeExactly 10232
        }

        It "Calculation for space used should work for servers < 2012" -Skip:$((Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).versionMajor -ge 11) {
            # Skip It on newer versions (so maybe remove test because it only targets unsupported versions)

            $db1Result = $results | Where-Object Database -eq $db1
            $db1Result.LogSpaceUsed | Should -Be ($db1Result.LogSize * ($db1Result.LogSpaceUsedPercent / 100))
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "LogSize",
                "LogSpaceUsedPercent",
                "LogSpaceUsed"
            )
            foreach ($prop in $expectedProperties) {
                $results[0].PSObject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist on the output object"
            }
        }

        It "LogSize is a dbasize object" {
            $results[0].LogSize | Should -BeOfType [dbasize]
        }

        It "LogSpaceUsed is a dbasize object" {
            $results[0].LogSpaceUsed | Should -BeOfType [dbasize]
        }
    }

    Context "System databases exclusions work" {
        BeforeAll {
            $results = Get-DbaDbLogSpace -SqlInstance $TestConfig.InstanceSingle -ExcludeSystemDatabase
        }

        It "Should exclude system databases" {
            $results.Database | Should -Not -BeIn @("model", "master", "tempdb", "msdb")
        }

        It "Should still contain $db1" {
            $results.Database | Should -Contain $db1
        }
    }

    Context "User databases exclusions work" {
        BeforeAll {
            $results = Get-DbaDbLogSpace -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $db1
        }

        It "Should include system databases" {
            @("model", "master", "tempdb", "msdb") | Should -BeIn $results.Database
        }

        It "Should not contain $db1" {
            $results.Database | Should -Not -Contain $db1
        }
    }

    Context "Piping servers works" {
        It "Should have database name of $db1" {
            $results = $TestConfig.InstanceSingle | Get-DbaDbLogSpace
            $results.Database | Should -Contain $db1
        }
    }
}
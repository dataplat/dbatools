#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbRecoveryModel",
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
                "RecoveryModel",
                "Database",
                "ExcludeDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Recovery model is correctly identified" {
        BeforeAll {
            $masterResults = Get-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -Database master -OutVariable "global:dbatoolsciOutput"
            $allResults = Get-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle
        }

        It "returns a single database" {
            $masterResults.Status.Count | Should -BeExactly 1
        }

        It "returns the correct recovery model" {
            $masterResults.RecoveryModel -eq "Simple" | Should -BeTrue
        }

        It "returns accurate number of results" {
            $allResults.Status.Count -ge 4 | Should -BeTrue
        }
    }

    Context "RecoveryModel parameter works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $dbname = "dbatoolsci_getrecoverymodel"
            Get-DbaDatabase -SqlInstance $server -Database $dbname | Remove-DbaDatabase
            $server.Query("CREATE DATABASE $dbname; ALTER DATABASE $dbname SET RECOVERY BULK_LOGGED WITH NO_WAIT;")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase -ErrorAction SilentlyContinue
        }

        It "gets the newly created database with the correct recovery model" {
            $results = Get-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            $results.RecoveryModel -eq "BulkLogged" | Should -BeTrue
        }

        It "honors the RecoveryModel parameter filter" {
            $results = Get-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel BulkLogged
            $results.Name -contains $dbname | Should -BeTrue
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Status",
                "IsAccessible",
                "RecoveryModel",
                "LastFullBackup",
                "LastDiffBackup",
                "LastLogBackup"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Database"
        }
    }
}
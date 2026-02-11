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
            $masterResults = Get-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -Database master
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
        BeforeAll {
            $result = Get-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -Database master
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Database"
        }

        It "Has the expected default display properties" {
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
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
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastFullBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastFullBackup"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["LastDiffBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastDiffBackup"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["LastLogBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastLogBackup"].MemberType | Should -Be "AliasProperty"
        }
    }
}
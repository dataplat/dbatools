#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbClone",
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
                "InputObject",
                "CloneDatabase",
                "ExcludeStatistics",
                "ExcludeQueryStore",
                "UpdateStatistics",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command functions as expected" {
        BeforeAll {
            $dbname = "dbatoolsci_clonetest"
            $clonedb = "dbatoolsci_clonetest_CLONE"
            $clonedb2 = "dbatoolsci_clonetest_CLONE2"

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $dbname")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase
        }

        It "warns if destination database already exists" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "exists"
        }

        It "warns if a system db is specified to clone" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "user database"
        }

        It "returns 1 result" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue
            $results | Should -HaveCount 1
            $results.Name | Should -Be $clonedb
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputDbName = "dbatoolsci_cloneoutput"
            $outputCloneName = "dbatoolsci_cloneoutput_CLONE"

            $outputServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $outputServer.Query("CREATE DATABASE $outputDbName")

            $result = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -CloneDatabase $outputCloneName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName, $outputCloneName | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
                "LogReuseWaitStatus",
                "SizeMB",
                "Compatibility",
                "Collation",
                "Owner",
                "Encrypted",
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
            $result[0].psobject.Properties["SizeMB"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["SizeMB"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["Compatibility"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Compatibility"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["Encrypted"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Encrypted"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["LastFullBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastFullBackup"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["LastDiffBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastDiffBackup"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["LastLogBackup"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["LastLogBackup"].MemberType | Should -Be "AliasProperty"
        }
    }
}
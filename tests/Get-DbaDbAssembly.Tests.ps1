#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbAssembly",
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
                "Name",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting database assemblies" {
        BeforeAll {
            $assemblyResults = Get-DbaDbAssembly -SqlInstance $TestConfig.InstanceSingle | Where-Object { $PSItem.parent.name -eq "master" }
            $masterDatabase = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master
        }

        It "Returns assembly objects" {
            $assemblyResults | Should -Not -BeNullOrEmpty
            $assemblyResults.DatabaseId | Should -BeExactly $masterDatabase.Id
        }

        It "Has the correct assembly name" {
            $assemblyResults.name | Should -BeExactly "Microsoft.SqlServer.Types"
        }

        It "Has the correct owner" {
            $assemblyResults.owner | Should -BeExactly "sys"
        }

        It "Has a version matching the instance" {
            $assemblyResults.Version | Should -BeExactly $masterDatabase.assemblies.Version
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaDbAssembly -SqlInstance $TestConfig.InstanceSingle -Database master
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.SqlAssembly"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ID",
                "Name",
                "Owner",
                "SecurityLevel",
                "CreateDate",
                "IsSystemObject",
                "Version"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias property SecurityLevel" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["SecurityLevel"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["SecurityLevel"].MemberType | Should -Be "AliasProperty"
        }
    }
}
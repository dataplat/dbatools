#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaServerRole",
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
                "ServerRole",
                "ExcludeServerRole",
                "ExcludeFixedRole",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaServerRole -SqlInstance $TestConfig.InstanceSingle
        }

        It "Should have correct properties" {
            $expectedProps = "ComputerName,DatabaseEngineEdition,DatabaseEngineType,DateCreated,DateModified,Events,ExecutionManager,ID,InstanceName,IsFixedRole,Login,Name,Owner,Parent,ParentCollection,Properties,Role,ServerRole,ServerVersion,SqlInstance,State,Urn,UserData".Split(",")
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Shows only one value with ServerRole parameter" {
            $singleResult = Get-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ServerRole sysadmin
            $singleResult[0].Role | Should -Be "sysadmin"
        }

        It "Should exclude sysadmin from output" {
            $excludeResults = Get-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ExcludeServerRole sysadmin
            "sysadmin" -NotIn $excludeResults.Role | Should -Be $true
        }

        It "Should exclude fixed server-level roles" {
            $excludeFixedResults = Get-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -ExcludeFixedRole
            "sysadmin" -NotIn $excludeFixedResults.Role | Should -Be $true
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputResult = Get-DbaServerRole -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.ServerRole"
        }

        It "Has the expected default display properties" {
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Role",
                "Login",
                "Owner",
                "IsFixedRole",
                "DateCreated",
                "DateModified"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}
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
    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaServerRole -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ServerRole]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Role',
                'Login',
                'Owner',
                'IsFixedRole',
                'DateCreated',
                'DateModified'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the dbatools-added properties" {
            $dbatoolsProps = @(
                'Login',
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Role',
                'ServerRole'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $dbatoolsProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be added by dbatools"
            }
        }
    }

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
}
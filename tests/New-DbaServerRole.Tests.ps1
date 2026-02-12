#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaServerRole",
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
                "Owner",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $roleExecutor = "serverExecuter"
        $roleMaster = "serverMaster"
        $owner = "sa"
    }
    AfterEach {
        $null = Remove-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor, $roleMaster
    }

    Context "Functionality" {
        It 'Add new server-role and returns results' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $script:outputForValidation = $result
        }

        It 'Add new server-role with specificied owner' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -Owner $owner

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $result.Owner | Should -Be $owner
        }

        It 'Add two new server-roles and returns results' {
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor, $roleMaster

            $result.Count | Should -Be 2
            $result.Name | Should -Contain $roleExecutor
            $result.Name | Should -Contain $roleMaster
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                $result = $script:outputForValidation
                $result | Should -Not -BeNullOrEmpty
                $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.ServerRole"
            }

            It "Has the expected default display properties" {
                $result = $script:outputForValidation
                $result | Should -Not -BeNullOrEmpty
                $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Role", "Login", "Owner", "IsFixedRole", "DateCreated", "DateModified")
                foreach ($prop in $expectedDefaults) {
                    $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                }
            }
        }
    }

}
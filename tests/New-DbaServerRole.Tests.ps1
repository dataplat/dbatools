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
            $result = New-DbaServerRole -SqlInstance $instance -ServerRole $roleExecutor -OutVariable "global:dbatoolsciOutput"

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
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
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ServerRole]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.ServerRole"
        }
    }
}
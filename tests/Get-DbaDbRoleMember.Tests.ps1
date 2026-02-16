#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbRoleMember",
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
                "Role",
                "ExcludeRole",
                "ExcludeFixedRole",
                "IncludeSystemUser",
                "InputObject",
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

        $instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $allDatabases = $instance.Databases

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # No specific cleanup needed for this test as we're only reading data

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Excludes system users by default" {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -OutVariable "global:dbatoolsciOutput"

            $result.IsSystemObject | Select-Object -Unique | Should -Not -Contain $true
        }

        It "Includes system users" {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -IncludeSystemUser

            $result.SmoUser.IsSystemObject | Select-Object -Unique | Should -Contain $true
        }

        It "Returns all role membership for all databases" {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -IncludeSystemUser

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly $allDatabases.Count
        }

        It "Accepts a list of databases" {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -Database "msdb" -IncludeSystemUser

            $result.Database | Select-Object -Unique | Should -Be "msdb"
        }

        It "Excludes databases" {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -ExcludeDatabase "msdb" -IncludeSystemUser

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly ($allDatabases.Count - 1)
            $uniqueDatabases | Should -Not -Contain "msdb"
        }

        It "Accepts a list of roles" {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -Role "db_owner" -IncludeSystemUser

            $result.Role | Select-Object -Unique | Should -Be "db_owner"
        }

        It "Excludes roles" {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -ExcludeRole "db_owner" -IncludeSystemUser

            $result.Role | Select-Object -Unique | Should -Not -Contain "db_owner"
        }

        It "Excludes fixed roles" {
            $result = Get-DbaDbRoleMember -SqlInstance $instance -ExcludeFixedRole -IncludeSystemUser

            $result.Role | Select-Object -Unique | Should -Not -Contain "db_owner"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Role",
                "UserName",
                "Login",
                "MemberRole",
                "SmoRole",
                "SmoUser",
                "SmoMemberRole"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
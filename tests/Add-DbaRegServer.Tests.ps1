#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaRegServer",
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
                "ServerName",
                "Name",
                "Description",
                "Group",
                "ActiveDirectoryTenant",
                "ActiveDirectoryUserId",
                "ConnectionString",
                "OtherParams",
                "InputObject",
                "ServerObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"
        $groupobject = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $group

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.instance1, $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1, $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When adding a registered server" {
        BeforeAll {
            $results1 = Add-DbaRegServer -SqlInstance $TestConfig.instance1 -ServerName $srvName
        }

        It "Adds a registered server with correct name" {
            $results1.Name | Should -Be $srvName
        }

        It "Adds a registered server with correct server name" {
            $results1.ServerName | Should -Be $srvName
        }

        It "Adds a registered server with non-null SqlInstance" {
            $results1.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "When adding a registered server with extended properties" {
        BeforeAll {
            $splatRegServer = @{
                SqlInstance = $TestConfig.instance1
                ServerName  = $regSrvName
                Name        = $srvName
                Group       = $groupobject
                Description = $regSrvDesc
            }

            $results2 = Add-DbaRegServer @splatRegServer
        }

        It "Adds a registered server with correct server name" {
            $results2.ServerName | Should -Be $regSrvName
        }

        It "Adds a registered server with correct description" {
            $results2.Description | Should -Be $regSrvDesc
        }

        It "Adds a registered server with correct name" {
            $results2.Name | Should -Be $srvName
        }

        It "Adds a registered server with non-null SqlInstance" {
            $results2.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
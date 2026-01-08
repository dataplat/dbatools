#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Watch-DbaDbLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "Table",
                "SqlCredential",
                "SqlCms",
                "ServersFromFile",
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

        $random = Get-Random

        $testFile = "$($TestConfig.Temp)\Servers_$random.txt"

        $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Out-File $testFile

        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

        $null = Add-DbaRegServer -SqlInstance $TestConfig.InstanceMulti1 -ServerName $TestConfig.InstanceMulti2 -Name "dbatoolsci_instance_$random"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.InstanceMulti1 | Remove-DbaRegServer
        Remove-Item -Path $testFile

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        # We can only test that the command does not write any warning.
        # A real test would need a very complex setup.

        It "ServersFromFile" {
            Watch-DbaDbLogin -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -ServersFromFile $testFile
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Pipeline of instances" {
            $server1, $server2 | Watch-DbaDbLogin -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb
            $WarnVar | Should -BeNullOrEmpty
        }

        It "ServersFromCMS" {
            Watch-DbaDbLogin -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -SqlCms $TestConfig.InstanceMulti1
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaLinkedServerConnection",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        Get-DbaProcess -SqlInstance $TestConfig.instance1 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -Database master
        $global:server.Query("EXEC master.dbo.sp_addlinkedserver @server = N'localhost', @srvproduct=N'SQL Server'")
    }

    AfterAll {
        Get-DbaProcess -SqlInstance $TestConfig.instance1 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -Database master
        $global:server.Query("EXEC master.dbo.sp_dropserver @server=N'localhost', @droplogins='droplogins'")
    }

    Context "Function works" {
        BeforeAll {
            $global:results = Test-DbaLinkedServerConnection -SqlInstance $TestConfig.instance1 | Where-Object LinkedServerName -eq "localhost"
        }

        It "function returns results" {
            $global:results | Should -Not -BeNullOrEmpty
        }

        It "linked server name is localhost" {
            $global:results.LinkedServerName | Should -Be "localhost"
        }

        It "connectivity is true" {
            $global:results.Connectivity | Should -BeTrue
        }
    }

    Context "Piping to function works" {
        BeforeAll {
            $global:pipeResults = Get-DbaLinkedServer -SqlInstance $TestConfig.instance1 | Test-DbaLinkedServerConnection
        }

        It "piping from Get-DbaLinkedServerConnection returns results" {
            $global:pipeResults | Should -Not -BeNullOrEmpty
        }

        It "linked server name is localhost" {
            $global:pipeResults.LinkedServerName | Should -Be "localhost"
        }

        It "connectivity is true" {
            $global:pipeResults.Connectivity | Should -BeTrue
        }
    }
}
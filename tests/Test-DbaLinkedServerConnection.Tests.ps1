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
        $port = (Get-DbaTcpPort -SqlInstance $TestConfig.InstanceSingle).Port
        $target = "localhost:$port"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        if ($server.VersionMajor -ge 17) {
            # Starting with SQL Server 2025 (17.x), MSOLEDBSQL uses Microsoft OLE DB Driver version 19, which adds support for TDS 8.0. However, this driver introduces a breaking change. You must now specify the encrypt parameter.
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$target', @srvproduct=N'', @provider=N'MSOLEDBSQL', @provstr = N'encrypt=optional;TrustServerCertificate=yes'")
        } elseif (-not $env:AppVeyor) {
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'localhost', @srvproduct=N'', @provider=N'MSOLEDBSQL'")
        } else {
            # AppVeyor images do not have the MSOLEDBSQL provider installed, so we use SQLNCLI11 instead
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$target', @srvproduct=N'', @provider=N'MSOLEDBSQL'")
        }
    }

    AfterAll {
        $server.Query("EXEC master.dbo.sp_dropserver @server=N'$target'")
    }

    Context "Function works" {
        BeforeAll {
            $results = Test-DbaLinkedServerConnection -SqlInstance $TestConfig.InstanceSingle | Where-Object LinkedServerName -eq $target
        }

        It "function returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "linked server name is correct" {
            $results.LinkedServerName | Should -Be $target
        }

        It "connectivity is true" {
            $results.Result | Should -Be 'Success'
            $results.Connectivity | Should -BeTrue
        }
    }

    Context "Piping to function works" {
        BeforeAll {
            $pipeResults = Get-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle | Test-DbaLinkedServerConnection
        }

        It "piping from Get-DbaLinkedServerConnection returns results" {
            $pipeResults | Should -Not -BeNullOrEmpty
        }

        It "linked server name is correct" {
            $pipeResults.LinkedServerName | Should -Be $target
        }

        It "connectivity is true" {
            $pipeResults.Result | Should -Be 'Success'
            $pipeResults.Connectivity | Should -BeTrue
        }
    }
}
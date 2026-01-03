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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        if ($server.VersionMajor -ge 17) {
            # Starting with SQL Server 2025 (17.x), MSOLEDBSQL uses Microsoft OLE DB Driver version 19, which adds support for TDS 8.0. However, this driver introduces a breaking change. You must now specify the encrypt parameter.
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'localhost', @srvproduct=N'', @provider=N'MSOLEDBSQL', @provstr = N'encrypt=optional;TrustServerCertificate=yes'")
        } elseif ($server.VersionMajor -eq 16) {
            # Starting with SQL Server 2022 (16.x), you must specify a provider name. MSOLEDBSQL is recommended. If you omit @provider, you can experience unexpected behavior.
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'localhost', @srvproduct=N'', @provider=N'MSOLEDBSQL'")
        } else {
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'localhost', @srvproduct=N'SQL Server'")
        }
    }

    AfterAll {
        $server.Query("EXEC master.dbo.sp_dropserver @server=N'localhost'")
    }

    Context "Function works" {
        BeforeAll {
            $results = Test-DbaLinkedServerConnection -SqlInstance $TestConfig.InstanceSingle | Where-Object LinkedServerName -eq "localhost"
        }

        It "function returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "linked server name is localhost" {
            $results.LinkedServerName | Should -Be "localhost"
        }

        It "connectivity is true" {
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

        It "linked server name is localhost" {
            $pipeResults.LinkedServerName | Should -Be "localhost"
        }

        It "connectivity is true" {
            $pipeResults.Connectivity | Should -BeTrue
        }
    }
}
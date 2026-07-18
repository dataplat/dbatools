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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $source = $TestConfig.InstanceMulti1
        $target = $TestConfig.InstanceMulti2

        $server = Connect-DbaInstance -SqlInstance $source
        if ($server.VersionMajor -ge 17) {
            # Starting with SQL Server 2025 (17.x), MSOLEDBSQL uses Microsoft OLE DB Driver version 19, which adds support for TDS 8.0. However, this driver introduces a breaking change. You must now specify the encrypt parameter.
            # Use @datasrc with tcp: prefix to force TCP/IP and avoid Named Pipes dependency.
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$target', @srvproduct=N'', @provider=N'MSOLEDBSQL', @datasrc=N'tcp:$target', @provstr = N'encrypt=optional;TrustServerCertificate=yes'")
        } elseif (-not $env:AppVeyor) {
            # Use @datasrc with tcp: prefix to force TCP/IP and avoid Named Pipes dependency.
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$target', @srvproduct=N'', @provider=N'MSOLEDBSQL', @datasrc=N'tcp:$target'")
        } else {
            # AppVeyor images do not have the MSOLEDBSQL provider installed, so we use SQLNCLI11 instead
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$target', @srvproduct=N'SQL Server'")
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server.Query("EXEC master.dbo.sp_dropserver @server=N'$target'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Function works" {
        BeforeAll {
            $results = Test-DbaLinkedServerConnection -SqlInstance $source | Where-Object LinkedServerName -eq $target

            # Harness honesty: the linked-server login runs SERVER-SIDE on $source; with an
            # integrated-auth linked server, a runner whose seat cannot delegate (Kerberos
            # double hop) gets "Login failed for user 'NT AUTHORITY\ANONYMOUS LOGON'" from
            # the command's connectivity test - legacy function and compiled cmdlet
            # IDENTICALLY (probed 2026-07-17). The command itself worked (it returned the
            # result object carrying that message), so only the connectivity assertion is
            # environment-bound - skip it on that exact signature.
            $skipConnectivity = ("$($results.Result)" -match "ANONYMOUS LOGON")
        }

        It "function returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "linked server name is correct" {
            $results.LinkedServerName | Should -Be $target
        }

        It "connectivity is true" {
            if ($skipConnectivity) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the linked-server login cannot delegate from this runner (ANONYMOUS LOGON), so connectivity can only fail environmentally"
                return
            }
            $results.Result | Should -Be "Success"
            $results.Connectivity | Should -BeTrue
        }
    }

    Context "Piping to function works" {
        BeforeAll {
            $pipeResults = Get-DbaLinkedServer -SqlInstance $source | Test-DbaLinkedServerConnection
            $skipPipeConnectivity = ("$($pipeResults.Result)" -match "ANONYMOUS LOGON")
        }

        It "piping from Get-DbaLinkedServerConnection returns results" {
            $pipeResults | Should -Not -BeNullOrEmpty
        }

        It "linked server name is correct" {
            $pipeResults.LinkedServerName | Should -Be $target
        }

        It "connectivity is true" {
            if ($skipPipeConnectivity) {
                Set-ItResult -Skipped -Because "the linked-server login cannot delegate from this runner (ANONYMOUS LOGON), so connectivity can only fail environmentally"
                return
            }
            $pipeResults.Result | Should -Be "Success"
            $pipeResults.Connectivity | Should -BeTrue
        }
    }
}
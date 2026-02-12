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

        $target = $TestConfig.InstanceSingle

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        if ($server.VersionMajor -ge 17) {
            # Starting with SQL Server 2025 (17.x), MSOLEDBSQL uses Microsoft OLE DB Driver version 19, which adds support for TDS 8.0. However, this driver introduces a breaking change. You must now specify the encrypt parameter.
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$target', @srvproduct=N'', @provider=N'MSOLEDBSQL', @provstr = N'encrypt=optional;TrustServerCertificate=yes'")
        } elseif (-not $env:AppVeyor) {
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$target', @srvproduct=N'', @provider=N'MSOLEDBSQL'")
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

        Context "Output validation" {
            It "Returns output of the documented type" {
                $results | Should -Not -BeNullOrEmpty
                $results[0].PSObject.TypeNames | Should -Contain "Dataplat.Dbatools.Validation.LinkedServerResult"
            }

            It "Has the expected properties" {
                if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
                $expectedProperties = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "LinkedServerName",
                    "RemoteServer",
                    "Connectivity",
                    "Result"
                )
                foreach ($prop in $expectedProperties) {
                    $results[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
                }
            }
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
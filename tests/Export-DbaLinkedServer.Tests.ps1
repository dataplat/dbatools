#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Export-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "LinkedServer",
                "SqlCredential",
                "Credential",
                "Path",
                "FilePath",
                "ExcludePassword",
                "Append",
                "Passthru",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Decryption behavior" -Skip:($IsLinux -or $IsMacOS) {
        BeforeAll {
            Mock Test-ExportDirectory { } -ModuleName dbatools
            Mock Test-FunctionInterrupt { $false } -ModuleName dbatools
            Mock Connect-DbaInstance {
                $mockLinkedServer = New-Object Microsoft.SqlServer.Management.Smo.LinkedServer
                $mockLinkedServer.Name = "linked1"
                $mockLinkedServer | Add-Member -MemberType ScriptMethod -Name Script -Value {
                    "EXEC sp_addlinkedserver @server=N'linked1'"
                } -Force

                $server = New-Object Microsoft.SqlServer.Management.Smo.Server "sql1"
                $server | Add-Member -MemberType NoteProperty -Name LinkedServers -Value @($mockLinkedServer) -Force
                $server
            } -ModuleName dbatools
            Mock Disconnect-DbaInstance { } -ModuleName dbatools
            Mock Get-ExportFilePath { "C:\temp\linkedservers.sql" } -ModuleName dbatools
            Mock Get-DecryptedObject {
                [PSCustomObject]@{
                    Name     = "linked1"
                    Identity = "remoteuser"
                    Password = "Password1!"
                }
            } -ModuleName dbatools
        }

        It "Should not force decryption errors to throw by default" {
            $null = Export-DbaLinkedServer -SqlInstance "sql1" -Passthru

            Should -Invoke -CommandName Get-DecryptedObject -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                -not $EnableException
            }
        }

        It "Should request terminating decryption errors when EnableException is specified" {
            $null = Export-DbaLinkedServer -SqlInstance "sql1" -Passthru -EnableException

            Should -Invoke -CommandName Get-DecryptedObject -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                $EnableException
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
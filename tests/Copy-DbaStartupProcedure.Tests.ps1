param($ModuleName = 'dbatools')

Describe "Copy-DbaStartupProcedure" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $procName = "dbatoolsci_test_startup"
        $server.Query("CREATE OR ALTER PROCEDURE $procName
                        AS
                        SELECT @@SERVERNAME
                        GO")
        $server.Query("EXEC sp_procoption @ProcName = N'$procName'
                            , @OptionName = 'startup'
                            , @OptionValue = 'on'")
    }

    AfterAll {
        Invoke-DbaQuery -SqlInstance $global:instance2, $global:instance3 -Database "master" -Query "DROP PROCEDURE dbatoolsci_test_startup"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaStartupProcedure
        }
        It "has all the required parameters" {
            $params = @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Procedure",
                "ExcludeProcedure",
                "Force",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Copy-DbaStartupProcedure -Source $global:instance2 -Destination $global:instance3
        }
        It "Should include test procedure: $procName" {
            ($results | Where-Object Name -eq $procName).Name | Should -Be $procName
        }
        It "Should be successful" {
            ($results | Where-Object Name -eq $procName).Status | Should -Be 'Successful'
        }
    }
}

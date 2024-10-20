param($ModuleName = 'dbatools')

Describe "Copy-DbaStartupProcedure" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaStartupProcedure
        }
        $knownParameters = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'Procedure',
            'ExcludeProcedure',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" {
            $command.Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters } | Should -Be $knownParameters
        }
    }

    Context "Command actually works" -ForEach @{ instance2 = $global:instance2; instance3 = $global:instance3 } {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $instance2
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
            Invoke-DbaQuery -SqlInstance $instance2, $instance3 -Database "master" -Query "DROP PROCEDURE IF EXISTS dbatoolsci_test_startup"
        }

        It "Should copy the startup procedure successfully" {
            $results = Copy-DbaStartupProcedure -Source $instance2 -Destination $instance3
            $copiedProcedure = $results | Where-Object Name -eq $procName

            $copiedProcedure.Name | Should -Be $procName
            $copiedProcedure.Status | Should -Be 'Successful'
        }
    }
}

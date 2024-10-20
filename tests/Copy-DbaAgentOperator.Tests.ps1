param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentOperator" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentOperator
        }
        $paramCount = 10
        $knownParameters = [object[]]@(
            'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential',
            'Operator', 'ExcludeOperator', 'Force', 'EnableException', 'WhatIf', 'Confirm'
        )
        It "Should contain <paramCount> parameters" {
            $command.Parameters.Count - $command.Parameters.Values.Where({$_.Attributes.DontShow}).Count | Should -Be $paramCount
        }
        It "Should contain parameter: <_>" -ForEach $knownParameters {
            $command | Should -HaveParameter $_
        }
    }

    Context "Copies operators" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
            $server.Query($sql)
            $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator2', @enabled=1, @pager_days=0"
            $server.Query($sql)
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
            $server.Query($sql)
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
            $server.Query($sql)

            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
            $server.Query($sql)
            $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
            $server.Query($sql)
        }

        It "returns two successful results" {
            $results = Copy-DbaAgentOperator -Source $global:instance2 -Destination $global:instance3 -Operator dbatoolsci_operator, dbatoolsci_operator2
            $results.Count | Should -Be 2
            $results.Status | Should -Be @("Successful", "Successful")
        }

        It "returns one skipped result" {
            $results = Copy-DbaAgentOperator -Source $global:instance2 -Destination $global:instance3 -Operator dbatoolsci_operator
            $results.Status | Should -Be "Skipped"
        }
    }
}

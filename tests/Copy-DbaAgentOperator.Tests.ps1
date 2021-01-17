$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Operator', 'ExcludeOperator', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator2', @enabled=1, @pager_days=0"
        $server.Query($sql)
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
        $server.Query($sql)
        $sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator2'"
        $server.Query($sql)
    }

    Context "Copies operators" {
        $results = Copy-DbaAgentOperator -Source $script:instance2 -Destination $script:instance3 -Operator dbatoolsci_operator, dbatoolsci_operator2

        It "returns two results" {
            $results.Count -eq 2
            $results.Status -eq "Successful", "Successful"
        }

        It "return one result that's skipped" {
            $results = Copy-DbaAgentOperator -Source $script:instance2 -Destination $script:instance3 -Operator dbatoolsci_operator
            $results.Status -eq "Skipped"
        }
    }
}
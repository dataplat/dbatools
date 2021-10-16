$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Database', 'ExcludeDatabase'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $tabletypename = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE TYPE $tabletypename AS TABLE([column1] INT NULL)", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP TYPE $tabletypename", 'tempdb')
    }

    Context "Gets the Db User Defined Table Type" {
        $results = Get-DbaDbUserDefinedTableType -SqlInstance $script:instance2 -database tempdb
        It "Gets results" {
            $results | Should Not Be $Null
        }
        It "Should have a name of $tabletypename" {
            $results.name | Should Be "$tabletypename"
        }
        It "Should have an owner of dbo" {
            $results.owner | Should Be "dbo"
        }
    }
}
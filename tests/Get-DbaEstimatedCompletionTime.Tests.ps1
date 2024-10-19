$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Get-DbaDatabase -SqlInstance $server -Database checkdbTestDatabase | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $server -Path $script:appveyorlabrepo\sql2008-backups\db1\FULL\SQL2008_db1_FULL_20170518_041738.bak -DatabaseName checkdbTestDatabase
        $null = New-DbaAgentJob -SqlInstance $server -Job checkdbTestJob
        $null = New-DbaAgentJobStep -SqlInstance $server -Job checkdbTestJob -StepName checkdb -Subsystem TransactSql -Command "DBCC CHECKDB('checkdbTestDatabase')"
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Remove-DbaAgentJob -SqlInstance $server -Job checkdbTestJob -Confirm:$false
        $null = Get-DbaDatabase -SqlInstance $server -Database checkdbTestDatabase | Remove-DbaDatabase -Confirm:$false
    }

    Context "Gets Query Estimated Completion" {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Start-DbaAgentJob -SqlInstance $server -Job checkdbTestJob
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $server
        Start-Sleep -Seconds 5
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be SELECT" {
            $results.Command | Should Match 'DBCC'
        }
        It "Should be login dbo" {
            $results.login | Should Be 'dbo'
        }
    }
    Context "Gets Query Estimated Completion when using -Database" {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Start-DbaAgentJob -SqlInstance $server -Job checkdbTestJob
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $server -Database checkdbTestDatabase
        Start-Sleep -Seconds 5
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be SELECT" {
            $results.Command | Should Match 'DBCC'
        }
        It "Should be login dbo" {
            $results.login | Should Be 'dbo'
        }
    }
    Context "Gets no Query Estimated Completion when using -ExcludeDatabase" {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Start-DbaAgentJob -SqlInstance $server -Job checkdbTestJob
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $server -ExcludeDatabase checkdbTestDatabase
        Start-Sleep -Seconds 5
        It "Gets no results" {
            $results | Should Be $null
        }
    }
}
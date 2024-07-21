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
        $null = New-DbaDatabase -SqlInstance $server -Name EstimatedCompletionTime
        Invoke-DbaQuery -SqlInstance $server -Database EstimatedCompletionTime -Query 'select * into dbo.messages from sys.messages'
        1 .. 10 | ForEach-Object { Invoke-DbaQuery -SqlInstance $server -Database EstimatedCompletionTime -Query 'insert into dbo.messages select * from sys.messages' }
        $null = New-DbaAgentJob -SqlInstance $server -Job EstimatedCompletionTime
        $null = New-DbaAgentJobStep -SqlInstance $server -Job EstimatedCompletionTime -StepName checkdb -Subsystem TransactSql -Command "DBCC CHECKDB('EstimatedCompletionTime')"
        $null = Start-DbaAgentJob -SqlInstance $script:instance2 -Job EstimatedCompletionTime
        Start-Sleep -Milliseconds 500
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Remove-DbaAgentJob -SqlInstance $server -Job EstimatedCompletionTime
        $null = Remove-DbaDatabase -SqlInstance $server -Database EstimatedCompletionTime
    }

    Context "Gets Query Estimated Completion" {
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $script:instance2
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be DBCC" {
            $results.Command | Should Match 'DBCC'
        }
        It "Should be login dbo" {
            $results.login | Should Be 'dbo'
        }
    }
    Context "Gets Query Estimated Completion when using -Database" {
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $script:instance2 -Database EstimatedCompletionTime
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should be DBCC" {
            $results.Command | Should Match 'DBCC'
        }
        It "Should be login dbo" {
            $results.login | Should Be 'dbo'
        }
    }
    Context "Gets no Query Estimated Completion when using -ExcludeDatabase" {
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $server -ExcludeDatabase EstimatedCompletionTime
        It "Gets no results" {
            $results | Should Be $null
        }
    }
}
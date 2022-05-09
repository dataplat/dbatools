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

    Context "Gets Query Estimated Completion" {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $biggestDatabase = Get-DbaDatabase -SqlInstance $server | Sort-Object SizeMB | Select-Object -Last 1 -ExpandProperty Name
        $null = New-DbaAgentJob -SqlInstance $server -Job checkdb
        $null = New-DbaAgentJobStep -SqlInstance $server -Job checkdb -StepName checkdb -Subsystem TransactSql -Command "DBCC CHECKDB('$biggestDatabase')"
        $null = Start-DbaAgentJob -SqlInstance $server -Job checkdb
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $server
        $null = Remove-DbaAgentJob -SqlInstance $server -Job checkdb -Confirm:$false
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
        $biggestDatabase = Get-DbaDatabase -SqlInstance $server | Sort-Object SizeMB | Select-Object -Last 1 -ExpandProperty Name
        $null = New-DbaAgentJob -SqlInstance $server -Job checkdb
        $null = New-DbaAgentJobStep -SqlInstance $server -Job checkdb -StepName checkdb -Subsystem TransactSql -Command "DBCC CHECKDB('$biggestDatabase')"
        $null = Start-DbaAgentJob -SqlInstance $server -Job checkdb
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $server -Database $biggestDatabase
        $null = Remove-DbaAgentJob -SqlInstance $server -Job checkdb -Confirm:$false
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
        $biggestDatabase = Get-DbaDatabase -SqlInstance $server | Sort-Object SizeMB | Select-Object -Last 1 -ExpandProperty Name
        $null = New-DbaAgentJob -SqlInstance $server -Job checkdb
        $null = New-DbaAgentJobStep -SqlInstance $server -Job checkdb -StepName checkdb -Subsystem TransactSql -Command "DBCC CHECKDB('$biggestDatabase')"
        $null = Start-DbaAgentJob -SqlInstance $server -Job checkdb
        $results = Get-DbaEstimatedCompletionTime -SqlInstance $server -ExcludeDatabase $biggestDatabase
        $null = Remove-DbaAgentJob -SqlInstance $server -Job checkdb -Confirm:$false
        Start-Sleep -Seconds 5
        It "Gets no results" {
            $results | Should Be $null
        }
    }
}
$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag "Unit" {
    Context "Ensure array" {
        $results = Get-Command -Name Get-DbaDatabaseFile | Select-Object -ExpandProperty ScriptBlock
        It "returns disks as an array" {
            $results -match '\$disks \= \@\(' | Should -Be $true
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "Count system databases on localhost" {
        $results = Get-DbaDatabaseFile -SqlInstance $script:instance1
        It "returns information about tempdb" {
            $results.Database -contains "tempdb" | Should -Be $true
        }
    }
    
    Context "Check that temppb database is in Simple recovery mode" {
        $results = Get-DbaDatabaseFile -SqlInstance $script:instance1 -Database tempdb
        foreach ($result in $results) {
            It "returns only information about tempdb" {
                $result.Database | Should -Be "tempdb"
            }
        }
    }
    
    Context "Physical name is populated" {
        $results = Get-DbaDatabaseFile -SqlInstance $script:instance1 -Database master
        It "master returns proper results" {
            $result = $results | Where-Object LogicalName -eq 'master'
            $result.PhysicalName -match 'master.mdf' | Should -Be $true
            $result = $results | Where-Object LogicalName -eq 'mastlog'
            $result.PhysicalName -match 'mastlog.ldf' | Should -Be $true
        }
    }
}
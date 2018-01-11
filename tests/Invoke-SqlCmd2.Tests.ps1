$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database tempdb -Query "Select 'hello' as TestColumn"
    It "returns a datatable" {
        $results.GetType().Name -eq "DataRow" | Should Be $true
    }

    It "returns the proper result" {
        $results.TestColumn -eq 'hello' | Should Be $true
    }

    $results = Invoke-SqlCmd2 -SqlInstance $script:instance1 -Database tempdb -Query "Select 'hello' as TestColumn"
    It "supports SQL instance param" {
        $results.TestColumn -eq 'hello' | Should Be $true
    }
}
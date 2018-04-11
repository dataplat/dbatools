$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $db = "dbatoolsci_writedbadaatable$random"
        $server.Query("CREATE DATABASE $db")
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $server -Database $db | Remove-DbaDatabase -Confirm:$false
    }

    # calling random function to throw data into a table
    It "defaults to dbo if no schema is specified" {
        $results = Get-ChildItem | ConvertTo-DbaDataTable
        $results | Write-DbaDataTable -SqlInstance $script:instance2 -Database $db -Table 'childitem' -AutoCreateTable

        ($server.Databases[$db].Tables | Where-Object { $_.Schema -eq 'dbo' -and $_.Name -eq 'childitem' }).Count | Should Be 1
    }
}
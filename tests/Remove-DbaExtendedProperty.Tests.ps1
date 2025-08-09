$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = Get-DbaProcess -SqlInstance $instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $newDbName = "dbatoolsci_newdb_$random"
        $db = New-DbaDatabase -SqlInstance $instance2 -Name $newDbName
    }

    AfterAll {
        $null = $db | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {
        It "works" {
            $ep = $db | Add-DbaExtendedProperty -Name "Test_Database_Name" -Value $newDbName
            $results = $ep | Remove-DbaExtendedProperty -Confirm:$false
            $results.Name | Should -Be "Test_Database_Name"
            $results.Status | Should -Be "Dropped"
        }
    }
}

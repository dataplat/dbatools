$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\New-DbaDatabase).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Collation', 'Recoverymodel', 'Owner', 'DataFilePath', 'LogFilePath', 'PrimaryFilesize', 'PrimaryFileGrowth', 'PrimaryFileMaxSize', 'LogSize', 'LogGrowth', 'SecondaryFilesize', 'SecondaryFileGrowth', 'SecondaryFileMaxSize', 'SecondaryFileCount', 'DefaultFileGroup', 'EnableException'
        $paramCount = $knownParameters.Count
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "commands work as expected" {
        $null = Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $results = New-DbaDatabase -SqlInstance $script:instance2
        It "creates one new randomly named database" {
            $results.Name | Should -Match random
            $results | Remove-DbaDatabase -Confirm:$false
        }

        $null = Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $results = New-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Name dbatoolsci_newdb
        It "creates one new database on two servers" {
            $results.Name | Should -Be 'dbatoolsci_newdb', 'dbatoolsci_newdb'
            $results | Remove-DbaDatabase -Confirm:$false
        }

        $null = Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $results = New-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Name dbatoolsci_newdb1, dbatoolsci_newdb2
        It "creates two new databases on two servers" {
            $results.Name | Should -Contain dbatoolsci_newdb1
            $results.Name | Should -Contain dbatoolsci_newdb2
            $results.Count | Should -Be 4
            $results | Remove-DbaDatabase -Confirm:$false
        }
    }
}
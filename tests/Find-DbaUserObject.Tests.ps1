$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Pattern', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command finds User Objects for SA" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_userObject' -Owner 'sa'
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database 'dbatoolsci_userObject' -Confirm:$false
        }

        $results = Find-DbaUserObject -SqlInstance $script:instance2 -Pattern sa
        It "Should find a specific Database Owned by sa" {
            $results.Where( {$_.name -eq 'dbatoolsci_userobject'}).Type | Should Be "Database"
        }
        It "Should find more than 10 objects Owned by sa" {
            $results.Count | Should BeGreaterThan 10
        }
    }
    Context "Command finds User Objects" {
        $results = Find-DbaUserObject -SqlInstance $script:instance2
        It "Should find resutls" {
            $results | Should Not Be Null
        }
    }
}
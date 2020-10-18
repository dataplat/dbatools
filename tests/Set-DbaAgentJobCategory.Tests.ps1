$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Category', 'NewName', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Job Category is changed properly" {

        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category CategoryTest1
            $results.Name | Should Be "CategoryTest1"
            $results.CategoryType | Should Be "LocalJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $script:instance2 -Category CategoryTest1
            $newresults.Name | Should Be "CategoryTest1"
            $newresults.CategoryType | Should Be "LocalJob"
        }

        It "Change the name of the job category" {
            $results = Set-DbaAgentJobCategory -SqlInstance $script:instance2 -Category CategoryTest1 -NewName CategoryTest2
            $results.Name | Should Be "CategoryTest2"
        }

        # Cleanup and ignore all output
        Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category CategoryTest2 *> $null
    }
}
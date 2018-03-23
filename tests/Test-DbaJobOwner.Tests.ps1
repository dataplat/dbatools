$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaJobOwner).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'Login', 'EnableException', 'Detailed'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $saJob = ("dbatoolsci_sa_{0}" -f $(Get-Random))
        $notSaJob = ("dbatoolsci_nonsa_{0}" -f $(Get-Random))
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job $saJob -OwnerLogin 'sa'
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job $notSaJob -OwnerLogin 'NT AUTHORITY\SYSTEM'
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job $saJob, $notSaJob
    }

    Context "Command actually works" {
        $results = Test-DbaJobOwner -SqlInstance $script:instance2
        It "Should return $notSaJob"{
            $results | Where-Object {$_.Job -eq $notsajob} | Should Not Be Null
        }
    }

    Context "Command works for specific jobs" {
        $results = Test-DbaJobOwner -SqlInstance $script:instance2 -Job $saJob, $notSaJob
        It "Should find $sajob owner matches default sa"{
            $($results | Where-Object {$_.Job -eq $sajob}).OwnerMatch | Should Be $True
        }
        It "Should find $notSaJob owner doesn't match default sa"{
            $($results | Where-Object {$_.Job -eq $notSaJob}).OwnerMatch | Should Be $False
        }
    }

    Context "Exclusions work" {
        $results = Test-DbaJobOwner -SqlInstance $script:instance2 -ExcludeJob $notSaJob
        It "Should exclude $notsajob job"{
            $results.job | Should Not Match $notSaJob
        }
    }
}
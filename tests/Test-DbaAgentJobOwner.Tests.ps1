$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'Login', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $saJob = ("dbatoolsci_sa_{0}" -f $(Get-Random))
        $notSaJob = ("dbatoolsci_nonsa_{0}" -f $(Get-Random))
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $saJob -OwnerLogin 'sa'
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $notSaJob -OwnerLogin 'NT AUTHORITY\SYSTEM'
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $saJob, $notSaJob -Confirm:$false
    }

    Context "Command actually works" {
        $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.instance2
        It "Should return $notSaJob" {
            $results | Where-Object { $_.Job -eq $notSaJob } | Should -Not -Be Null
        }
    }

    Context "Command works for specific jobs" {
        $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.instance2 -Job $saJob, $notSaJob
        It "Should find $saJob owner matches default sa" {
            $($results | Where-Object { $_.Job -eq $saJob }).OwnerMatch | Should -Be $True
        }
        It "Should find $notSaJob owner doesn't match default sa" {
            $($results | Where-Object { $_.Job -eq $notSaJob }).OwnerMatch | Should -Be $False
        }
    }

    Context "Exclusions work" {
        $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.instance2 -ExcludeJob $notSaJob
        It "Should exclude $notSaJob job" {
            $results.job | Should -Not -Match $notSaJob
        }
    }
}
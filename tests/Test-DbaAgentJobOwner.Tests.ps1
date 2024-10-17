param($ModuleName = 'dbatools')

Describe "Test-DbaAgentJobOwner Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaAgentJobOwner
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob -Type Object[] -Not -Mandatory
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "Test-DbaAgentJobOwner Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $saJob = ("dbatoolsci_sa_{0}" -f $(Get-Random))
        $notSaJob = ("dbatoolsci_nonsa_{0}" -f $(Get-Random))
        $null = New-DbaAgentJob -SqlInstance $env:instance2 -Job $saJob -OwnerLogin 'sa'
        $null = New-DbaAgentJob -SqlInstance $env:instance2 -Job $notSaJob -OwnerLogin 'NT AUTHORITY\SYSTEM'
    }

    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $env:instance2 -Job $saJob, $notSaJob -Confirm:$false
    }

    Context "Command actually works" {
        It "Should return $notSaJob" {
            $results = Test-DbaAgentJobOwner -SqlInstance $env:instance2
            $results | Where-Object {$_.Job -eq $notSaJob} | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command works for specific jobs" {
        BeforeAll {
            $results = Test-DbaAgentJobOwner -SqlInstance $env:instance2 -Job $saJob, $notSaJob
        }

        It "Should find $saJob owner matches default sa" {
            ($results | Where-Object {$_.Job -eq $saJob}).OwnerMatch | Should -BeTrue
        }

        It "Should find $notSaJob owner doesn't match default sa" {
            ($results | Where-Object {$_.Job -eq $notSaJob}).OwnerMatch | Should -BeFalse
        }
    }

    Context "Exclusions work" {
        It "Should exclude $notSaJob job" {
            $results = Test-DbaAgentJobOwner -SqlInstance $env:instance2 -ExcludeJob $notSaJob
            $results.job | Should -Not -Contain $notSaJob
        }
    }
}

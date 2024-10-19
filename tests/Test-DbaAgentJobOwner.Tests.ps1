param($ModuleName = 'dbatools')

Describe "Test-DbaAgentJobOwner Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaAgentJobOwner
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job
        }
        It "Should have ExcludeJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
        $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job $saJob -OwnerLogin 'sa'
        $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job $notSaJob -OwnerLogin 'NT AUTHORITY\SYSTEM'
    }

    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job $saJob, $notSaJob -Confirm:$false
    }

    Context "Command actually works" {
        It "Should return $notSaJob" {
            $results = Test-DbaAgentJobOwner -SqlInstance $global:instance2
            $results | Where-Object {$_.Job -eq $notSaJob} | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command works for specific jobs" {
        BeforeAll {
            $results = Test-DbaAgentJobOwner -SqlInstance $global:instance2 -Job $saJob, $notSaJob
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
            $results = Test-DbaAgentJobOwner -SqlInstance $global:instance2 -ExcludeJob $notSaJob
            $results.job | Should -Not -Contain $notSaJob
        }
    }
}

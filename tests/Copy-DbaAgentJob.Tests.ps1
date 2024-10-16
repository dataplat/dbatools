param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentJob" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaAgentJob
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[]
        }
        It "Should have ExcludeJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob -Type Object[]
        }
        It "Should have DisableOnSource as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableOnSource -Type Switch
        }
        It "Should have DisableOnDestination as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableOnDestination -Type Switch
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Job[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command copies jobs properly" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_copyjob
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_copyjob_disabled
            $sourcejobs = Get-DbaAgentJob -SqlInstance $script:instance2
            $destjobs = Get-DbaAgentJob -SqlInstance $script:instance3
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -Confirm:$false
            $null = Remove-DbaAgentJob -SqlInstance $script:instance3 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -Confirm:$false
        }

        It "returns one success" {
            $results = Copy-DbaAgentJob -Source $script:instance2 -Destination $script:instance3 -Job dbatoolsci_copyjob
            $results.Name | Should -Be "dbatoolsci_copyjob"
            $results.Status | Should -Be "Successful"
        }

        It "did not copy dbatoolsci_copyjob_disabled" {
            $job = Get-DbaAgentJob -SqlInstance $script:instance3 -Job dbatoolsci_copyjob_disabled
            $job | Should -BeNullOrEmpty
        }

        It "disables jobs when requested" {
            $sourceJob = Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_copyjob_disabled
            $sourceJob.Enabled | Should -BeTrue

            $results = Copy-DbaAgentJob -Source $script:instance2 -Destination $script:instance3 -Job dbatoolsci_copyjob_disabled -DisableOnSource -DisableOnDestination -Force
            $results.Name | Should -Be "dbatoolsci_copyjob_disabled"
            $results.Status | Should -Be "Successful"

            $sourceJobAfter = Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_copyjob_disabled
            $sourceJobAfter.Enabled | Should -BeFalse

            $destJob = Get-DbaAgentJob -SqlInstance $script:instance3 -Job dbatoolsci_copyjob_disabled
            $destJob.Enabled | Should -BeFalse
        }
    }
}

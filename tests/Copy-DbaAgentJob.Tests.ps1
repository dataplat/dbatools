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
            $CommandUnderTest | Should -HaveParameter Source
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job
        }
        It "Should have ExcludeJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob
        }
        It "Should have DisableOnSource as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableOnSource
        }
        It "Should have DisableOnDestination as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableOnDestination
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command copies jobs properly" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob_disabled
            $sourcejobs = Get-DbaAgentJob -SqlInstance $global:instance2
            $destjobs = Get-DbaAgentJob -SqlInstance $global:instance3
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -Confirm:$false
            $null = Remove-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_copyjob, dbatoolsci_copyjob_disabled -Confirm:$false
        }

        It "returns one success" {
            $results = Copy-DbaAgentJob -Source $global:instance2 -Destination $global:instance3 -Job dbatoolsci_copyjob
            $results.Name | Should -Be "dbatoolsci_copyjob"
            $results.Status | Should -Be "Successful"
        }

        It "did not copy dbatoolsci_copyjob_disabled" {
            $job = Get-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_copyjob_disabled
            $job | Should -BeNullOrEmpty
        }

        It "disables jobs when requested" {
            $sourceJob = Get-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob_disabled
            $sourceJob.Enabled | Should -BeTrue

            $results = Copy-DbaAgentJob -Source $global:instance2 -Destination $global:instance3 -Job dbatoolsci_copyjob_disabled -DisableOnSource -DisableOnDestination -Force
            $results.Name | Should -Be "dbatoolsci_copyjob_disabled"
            $results.Status | Should -Be "Successful"

            $sourceJobAfter = Get-DbaAgentJob -SqlInstance $global:instance2 -Job dbatoolsci_copyjob_disabled
            $sourceJobAfter.Enabled | Should -BeFalse

            $destJob = Get-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_copyjob_disabled
            $destJob.Enabled | Should -BeFalse
        }
    }
}

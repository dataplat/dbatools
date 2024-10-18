param($ModuleName = 'dbatools')

Describe "Set-DbaPowerPlan" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaPowerPlan
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have PowerPlan as a parameter" {
            $CommandUnderTest | Should -HaveParameter PowerPlan -Type System.String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $null = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan 'Balanced'
        }

        It "Should return result for the server" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME
            $results | Should -Not -BeNull
            $results.ActivePowerPlan | Should -Be 'High Performance'
            $results.IsChanged | Should -BeTrue
        }

        It "Should skip if already set" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME
            $results.ActivePowerPlan | Should -Be 'High Performance'
            $results.IsChanged | Should -BeFalse
            $results.ActivePowerPlan | Should -Be $results.PreviousPowerPlan
        }

        It "Should return result for the server when setting defined PowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -PowerPlan Balanced
            $results | Should -Not -BeNull
            $results.ActivePowerPlan | Should -Be 'Balanced'
            $results.IsChanged | Should -BeTrue
        }

        It "Should accept Piped input for ComputerName" {
            $results = $env:COMPUTERNAME | Set-DbaPowerPlan
            $results | Should -Not -BeNull
            $results.ActivePowerPlan | Should -Be 'High Performance'
            $results.IsChanged | Should -BeTrue
        }

        It "Should return result for the server when using the alias CustomPowerPlan" {
            $results = Set-DbaPowerPlan -ComputerName $env:COMPUTERNAME -CustomPowerPlan Balanced
            $results | Should -Not -BeNull
            $results.ActivePowerPlan | Should -Be 'Balanced'
            $results.IsChanged | Should -BeTrue
        }
    }
}

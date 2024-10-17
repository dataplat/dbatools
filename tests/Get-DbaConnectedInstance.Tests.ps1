param($ModuleName = 'dbatools')

Describe "Get-DbaConnectedInstance" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaConnectedInstance
        }
        It "Should have the expected parameters" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type switch -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter Debug -Type switch -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter WarningAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter InformationAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type string -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type string -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type string -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter OutVariable -Type string -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type int -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type string -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance1
        }

        It "returns some results" {
            $results = Get-DbaConnectedInstance
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

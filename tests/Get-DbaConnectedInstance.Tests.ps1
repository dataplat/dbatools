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
            $CommandUnderTest | Should -HaveParameter Verbose -Type switch -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Debug -Type switch -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type string -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type string -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type string -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OutVariable -Type string -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type int -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type string -Not -Mandatory
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

param($ModuleName = 'dbatools')

Describe "Get-DbaNetworkActivity" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaNetworkActivity
        }
        It "Should have ComputerName as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type String[] -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Should have common parameters" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
    }

    Context "Gets Network Activity" {
        BeforeAll {
            $results = Get-DbaNetworkActivity -ComputerName $env:ComputerName
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

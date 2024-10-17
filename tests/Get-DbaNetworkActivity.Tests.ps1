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
            $CommandUnderTest | Should -HaveParameter ComputerName -Type String[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
        It "Should have common parameters" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Mandatory:$false
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Mandatory:$false
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

param($ModuleName = 'dbatools')

Describe "Get-DbaPageFileSetting" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPageFileSetting
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
        It "Should have Verbose as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type switch -Mandatory:$false
        }
        It "Should have Debug as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type switch -Mandatory:$false
        }
        It "Should have ErrorAction as a non-mandatory parameter of type System.Management.Automation.ActionPreference" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
        }
        It "Should have WarningAction as a non-mandatory parameter of type System.Management.Automation.ActionPreference" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
        }
        It "Should have InformationAction as a non-mandatory parameter of type System.Management.Automation.ActionPreference" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
        }
        It "Should have ProgressAction as a non-mandatory parameter of type System.Management.Automation.ActionPreference" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
        }
        It "Should have ErrorVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Mandatory:$false
        }
        It "Should have WarningVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Mandatory:$false
        }
        It "Should have InformationVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Mandatory:$false
        }
        It "Should have OutVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Mandatory:$false
        }
        It "Should have OutBuffer as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Mandatory:$false
        }
        It "Should have PipelineVariable as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Mandatory:$false
        }
    }

    Context "Gets PageFile Settings" {
        BeforeAll {
            $results = Get-DbaPageFileSetting -ComputerName $env:ComputerName
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}

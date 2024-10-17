param($ModuleName = 'dbatools')

Describe "Save-DbaDiagnosticQueryScript" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Save-DbaDiagnosticQueryScript
        }
        It "Should have Path as a non-mandatory parameter of type FileInfo" {
            $CommandUnderTest | Should -HaveParameter Path -Type FileInfo -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
        It "Should have Verbose as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Mandatory:$false
        }
        It "Should have Debug as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Mandatory:$false
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

    # Add more contexts and tests as needed for integration testing
    # For example:
    # Context "Integration Tests" {
    #     It "Should save the diagnostic query script" {
    #         # Test implementation
    #     }
    # }
}

param($ModuleName = 'dbatools')

Describe "Set-DbatoolsPath" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbatoolsPath
        }
        It "Should have Name as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Mandatory:$false
        }
        It "Should have Path as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Mandatory:$false
        }
        It "Should have Register as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Register -Type Switch -Mandatory:$false
        }
        It "Should have Scope as a non-mandatory ConfigScope parameter" {
            $CommandUnderTest | Should -HaveParameter Scope -Type ConfigScope -Mandatory:$false
        }
        It "Should have Verbose as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Mandatory:$false
        }
        It "Should have Debug as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Mandatory:$false
        }
        It "Should have ErrorAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Mandatory:$false
        }
        It "Should have WarningAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Mandatory:$false
        }
        It "Should have InformationAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Mandatory:$false
        }
        It "Should have ProgressAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Mandatory:$false
        }
        It "Should have ErrorVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Mandatory:$false
        }
        It "Should have WarningVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Mandatory:$false
        }
        It "Should have InformationVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Mandatory:$false
        }
        It "Should have OutVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Mandatory:$false
        }
        It "Should have OutBuffer as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Mandatory:$false
        }
        It "Should have PipelineVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Mandatory:$false
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Set-DbaMaxMemory" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $inst1CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $global:instance1).MaxValue
        $inst2CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $global:instance2).MaxValue
    }

    AfterAll {
        $null = Set-DbaMaxMemory -SqlInstance $global:instance1 -Max $inst1CurrentMaxValue
        $null = Set-DbaMaxMemory -SqlInstance $global:instance2 -Max $inst2CurrentMaxValue
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaMaxMemory
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Max parameter" {
            $CommandUnderTest | Should -HaveParameter Max
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Connects to multiple instances" {
        BeforeAll {
            $results = Set-DbaMaxMemory -SqlInstance $global:instance1, $global:instance2 -Max 1024
        }
        It 'Returns 1024 for each instance' {
            foreach ($result in $results) {
                $result.MaxValue | Should -Be 1024
            }
        }
    }
}

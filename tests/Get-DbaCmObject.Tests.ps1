param($ModuleName = 'dbatools')

Describe "Get-DbaCmObject" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCmObject
        }
        It "Should have ClassName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ClassName -Type String -Mandatory:$false
        }
        It "Should have Query as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Query -Type String -Mandatory:$false
        }
        It "Should have ComputerName as a non-mandatory DbaCmConnectionParameter[] parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaCmConnectionParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have Namespace as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Namespace -Type String -Mandatory:$false
        }
        It "Should have DoNotUse as a non-mandatory ManagementConnectionType[] parameter" {
            $CommandUnderTest | Should -HaveParameter DoNotUse -Type Dataplat.Dbatools.Connection.ManagementConnectionType[] -Mandatory:$false
        }
        It "Should have Force as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Mandatory:$false
        }
        It "Should have SilentlyContinue as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter SilentlyContinue -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        It "returns a bias that's an int" {
            $result = Get-DbaCmObject -ClassName Win32_TimeZone
            $result.Bias | Should -BeOfType [int]
        }
    }
}

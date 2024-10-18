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
        It "Should have ClassName as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter ClassName -Type System.String -Mandatory:$false
        }
        It "Should have Query as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Query -Type System.String -Mandatory:$false
        }
        It "Should have ComputerName as a non-mandatory Dataplat.Dbatools.Parameter.DbaCmConnectionParameter[] parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaCmConnectionParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory System.Management.Automation.PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Namespace as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Namespace -Type System.String -Mandatory:$false
        }
        It "Should have DoNotUse as a non-mandatory Dataplat.Dbatools.Connection.ManagementConnectionType[] parameter" {
            $CommandUnderTest | Should -HaveParameter DoNotUse -Type Dataplat.Dbatools.Connection.ManagementConnectionType[] -Mandatory:$false
        }
        It "Should have Force as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have SilentlyContinue as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter SilentlyContinue -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command usage" {
        It "returns a bias that's an int" {
            $result = Get-DbaCmObject -ClassName Win32_TimeZone
            $result.Bias | Should -BeOfType [int]
        }
    }
}

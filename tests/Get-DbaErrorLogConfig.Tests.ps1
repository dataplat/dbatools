param($ModuleName = 'dbatools')

Describe "Get-DbaErrorLogConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaErrorLogConfig
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Get NumberErrorLog for multiple instances" {
        BeforeAll {
            $results = Get-DbaErrorLogConfig -SqlInstance $global:instance3, $global:instance2
        }

        It 'returns 3 values for each result' {
            foreach ($result in $results) {
                $result.LogCount | Should -Not -BeNullOrEmpty
                $result.LogSize | Should -Not -BeNullOrEmpty
                $result.LogPath | Should -Not -BeNullOrEmpty
            }
        }
    }
}

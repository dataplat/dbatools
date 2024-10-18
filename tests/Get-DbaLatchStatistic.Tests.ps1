param($ModuleName = 'dbatools')

Describe "Get-DbaLatchStatistic" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaLatchStatistic
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Threshold as a parameter" {
            $CommandUnderTest | Should -HaveParameter Threshold -Type System.Int32 -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaLatchStatistic -SqlInstance $global:instance2 -Threshold 100
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "returns a hyperlink for each result" {
            foreach ($result in $results) {
                $result.URL | Should -Match 'sqlskills.com'
            }
        }
    }
}

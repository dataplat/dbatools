param($ModuleName = 'dbatools')

Describe "Export-DbaXESessionTemplate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaXESessionTemplate
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Session as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Session -Type System.Object[] -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String -Mandatory:$false
        }
        It "Should have FilePath as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type System.String -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.XEvent.Session[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.XEvent.Session[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Integration Tests" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $null = Get-DbaXESession -SqlInstance $global:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
        }

        AfterAll {
            $null = Get-DbaXESession -SqlInstance $global:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
            Remove-Item -Path 'C:\windows\temp\Profiler TSQL Duration.xml' -ErrorAction SilentlyContinue
        }

        It "Exports session to disk" {
            $session = Import-DbaXESessionTemplate -SqlInstance $global:instance2 -Template 'Profiler TSQL Duration'
            $results = $session | Export-DbaXESessionTemplate -Path C:\windows\temp
            $results.Name | Should -Be 'Profiler TSQL Duration.xml'
        }
    }
}

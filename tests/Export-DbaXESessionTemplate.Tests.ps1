param($ModuleName = 'dbatools')

Describe "Export-DbaXESessionTemplate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaXESessionTemplate
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Session as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Session -Type Object[] -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Mandatory:$false
        }
        It "Should have FilePath as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type String -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Session[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.XEvent.Session[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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

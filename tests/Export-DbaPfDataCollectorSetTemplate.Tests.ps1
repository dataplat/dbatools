param($ModuleName = 'dbatools')

Describe "Export-DbaPfDataCollectorSetTemplate" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaPfDataCollectorSetTemplate
        }
        It "Should have ComputerName as a non-mandatory DbaInstanceParameter[] parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have CollectorSet as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type System.String[] -Mandatory:$false
        }
        It "Should have Path as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String -Mandatory:$false
        }
        It "Should have FilePath as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type System.String -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }

    Context "Command usage" -Tag "IntegrationTests" {
        BeforeAll {
            $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
        }
        AfterAll {
            $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
        }

        It "returns a file system object when using pipeline input" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Export-DbaPfDataCollectorSetTemplate
            $results.BaseName | Should -Be 'Long Running Queries'
        }

        It "returns a file system object when using parameter input" {
            $results = Export-DbaPfDataCollectorSetTemplate -CollectorSet 'Long Running Queries'
            $results.BaseName | Should -Be 'Long Running Queries'
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Set-DbaDbFileGrowth" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbFileGrowth
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[]
        }
        It "Should have GrowthType as a parameter" {
            $CommandUnderTest | Should -HaveParameter GrowthType -Type System.String
        }
        It "Should have Growth as a parameter" {
            $CommandUnderTest | Should -HaveParameter Growth -Type System.Int32
        }
        It "Should have FileType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileType -Type System.String
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

Describe "Set-DbaDbFileGrowth Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $newdb = New-DbaDatabase -SqlInstance $global:instance2 -Name newdb
    }

    AfterAll {
        $newdb | Remove-DbaDatabase -Confirm:$false
    }

    Context "Should return file information for only newdb" {
        It "returns the proper info" {
            $result = Set-DbaDbFileGrowth -SqlInstance $global:instance2 -Database newdb | Select-Object -First 1
            $result.Database | Should -Be "newdb"
            $result.GrowthType | Should -Be "kb"
        }
    }

    Context "Supports piping" {
        It "returns only newdb files" {
            $result = Get-DbaDatabase $global:instance2 -Database newdb | Set-DbaDbFileGrowth | Select-Object -First 1
            $result.Database | Should -Be "newdb"
        }
    }
}

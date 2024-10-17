param($ModuleName = 'dbatools')

Describe "Set-DbaDbFileGrowth" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbFileGrowth
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have GrowthType as a parameter" {
            $CommandUnderTest | Should -HaveParameter GrowthType -Type String
        }
        It "Should have Growth as a parameter" {
            $CommandUnderTest | Should -HaveParameter Growth -Type Int32
        }
        It "Should have FileType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileType -Type String
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Set-DbaDbFileGrowth Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $newdb = New-DbaDatabase -SqlInstance $env:instance2 -Name newdb
    }

    AfterAll {
        $newdb | Remove-DbaDatabase -Confirm:$false
    }

    Context "Should return file information for only newdb" {
        It "returns the proper info" {
            $result = Set-DbaDbFileGrowth -SqlInstance $env:instance2 -Database newdb | Select-Object -First 1
            $result.Database | Should -Be "newdb"
            $result.GrowthType | Should -Be "kb"
        }
    }

    Context "Supports piping" {
        It "returns only newdb files" {
            $result = Get-DbaDatabase $env:instance2 -Database newdb | Set-DbaDbFileGrowth | Select-Object -First 1
            $result.Database | Should -Be "newdb"
        }
    }
}

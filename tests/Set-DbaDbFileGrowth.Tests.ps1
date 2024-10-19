param($ModuleName = 'dbatools')

Describe "Set-DbaDbFileGrowth" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbFileGrowth
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have GrowthType as a parameter" {
            $CommandUnderTest | Should -HaveParameter GrowthType
        }
        It "Should have Growth as a parameter" {
            $CommandUnderTest | Should -HaveParameter Growth
        }
        It "Should have FileType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileType
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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

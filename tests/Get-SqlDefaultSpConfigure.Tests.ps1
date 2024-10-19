param($ModuleName = 'dbatools')

Describe "Get-SqlDefaultSPConfigure" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Get-SqlDefaultSPConfigure.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-SqlDefaultSPConfigure
        }
        It "Should have SqlVersion as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlVersion
        }
    }

    Context "Try all versions of SQL" {
        BeforeAll {
            $versionName = @{
                8  = "2000"
                9  = "2005"
                10 = "2008/2008R2"
                11 = "2012"
                12 = "2014"
                13 = "2016"
                14 = "2017"
                15 = "2019"
                16 = "2022"
            }
        }

        It "Should return results for <versionName[$_]>" -ForEach (8..14) {
            $results = Get-SqlDefaultSPConfigure -SqlVersion $_
            $results | Should -Not -BeNullOrEmpty
            $results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject"
        }
    }
}

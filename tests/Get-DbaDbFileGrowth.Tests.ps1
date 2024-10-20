param($ModuleName = 'dbatools')

Describe "Get-DbaDbFileGrowth" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbFileGrowth
        }

        It "has the required parameter: SqlInstance" -ForEach @("SqlInstance", "SqlCredential") {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }

        It "has all the required parameters" {
            $requiredParameters = @(
                "Database",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        It "Should return file information" {
            $result = Get-DbaDbFileGrowth -SqlInstance $global:instance2
            $result.Database | Should -Contain "msdb"
        }

        It "Should return file information for only msdb" {
            $result = Get-DbaDbFileGrowth -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1
            $result.Database | Should -Be "msdb"
        }
    }
}

param($ModuleName = 'dbatools')

Describe "Set-DbaDbFileGrowth" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbFileGrowth
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "GrowthType",
            "Growth",
            "FileType",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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

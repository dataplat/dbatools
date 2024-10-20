param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedType" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedType
        }
        $params = @(
            "RandomizedType",
            "RandomizedSubType",
            "Pattern",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command returns types" {
        It "Should have at least 205 rows" {
            $types = Get-DbaRandomizedType
            $types.Count | Should -BeGreaterOrEqual 205
        }

        It "Should return correct type based on subtype" {
            $result = Get-DbaRandomizedType -RandomizedSubType Zipcode
            $result.Type | Should -Be "Address"
        }

        It "Should return values based on pattern" {
            $types = Get-DbaRandomizedType -Pattern Name
            $types.Count | Should -BeGreaterOrEqual 26
        }
    }
}

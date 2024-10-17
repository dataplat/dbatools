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
        It "Should have RandomizedType as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter RandomizedType -Type String[] -Not -Mandatory
        }
        It "Should have RandomizedSubType as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter RandomizedSubType -Type String[] -Not -Mandatory
        }
        It "Should have Pattern as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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

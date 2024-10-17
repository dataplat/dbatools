param($ModuleName = 'dbatools')

Describe "Copy-DbaXESessionTemplate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaXESessionTemplate
        }
        It "Should have Path as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Mandatory:$false
        }
        It "Should have Destination as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Destination -Type String -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Copies the files properly" {
            $null = Copy-DbaXESessionTemplate *>1
            $source = ((Get-DbaXESessionTemplate -Path $Path | Where-Object Source -ne Microsoft).Path | Select-Object -First 1).Name
            $result = Get-ChildItem "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates" | Where-Object Name -eq $source
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

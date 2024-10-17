param($ModuleName = 'dbatools')

Describe "Get-DbatoolsError" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsError
        }
        It "Accepts First as a parameter" {
            $CommandUnderTest | Should -HaveParameter First -Type Int32
        }
        It "Accepts Last as a parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type Int32
        }
        It "Accepts Skip as a parameter" {
            $CommandUnderTest | Should -HaveParameter Skip -Type Int32
        }
        It "Accepts All as a parameter" {
            $CommandUnderTest | Should -HaveParameter All -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "returns a dbatools error" {
            # Mock Connect-DbaInstance to throw an error
            Mock Connect-DbaInstance -ModuleName $ModuleName {
                throw "Test error"
            }

            try {
                $null = Connect-DbaInstance -SqlInstance nothing -ConnectTimeout 1 -ErrorAction Stop
            } catch {}

            $result = Get-DbatoolsError
            $result | Should -Not -BeNullOrEmpty
            $result.Exception.Message | Should -Be "Test error"
        }
    }
}

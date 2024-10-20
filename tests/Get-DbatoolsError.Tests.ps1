param($ModuleName = 'dbatools')

Describe "Get-DbatoolsError" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbatoolsError
        }
        $params = @(
            "First",
            "Last",
            "Skip",
            "All"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "returns a dbatools error" {
            # Mock Connect-DbaInstance to throw a specific error
            Mock Connect-DbaInstance -ModuleName $ModuleName {
                throw "Test error"
            }

            try {
                $null = Connect-DbaInstance -SqlInstance 'nothing' -ConnectTimeout 1 -ErrorAction Stop
            } catch {}

            $result = Get-DbatoolsError
            $result | Should -Not -BeNullOrEmpty
            $result.Exception.Message | Should -Be "Test error"
        }
    }
}

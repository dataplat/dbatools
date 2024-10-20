param($ModuleName = 'dbatools')

Describe "Get-DbaCpuRingBuffer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCpuRingBuffer
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "CollectionMinutes",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command returns proper info" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $results = Get-DbaCpuRingBuffer -SqlInstance $global:instance2 -CollectionMinutes 100
        }
        It "Returns results" {
            $results.Count | Should -BeGreaterThan 0
        }
    }
}

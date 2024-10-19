param($ModuleName = 'dbatools')

Describe "Get-DbaCpuRingBuffer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCpuRingBuffer
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "CollectionMinutes",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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

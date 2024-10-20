param($ModuleName = 'dbatools')

Describe "Get-DbaComputerSystem" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaComputerSystem
        }

        $params = @(
            "ComputerName",
            "Credential",
            "IncludeAws",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Validate input" {
        It "Throws when it cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName { $null }
            { Get-DbaComputerSystem -ComputerName 'DoesNotExist142' -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Validate output" -Skip:($null -ne $env:CI) {
        BeforeAll {
            $result = Get-DbaComputerSystem -ComputerName $global:instance1

            $props = 'ComputerName', 'Domain', 'IsDaylightSavingsTime', 'Manufacturer', 'Model', 'NumberLogicalProcessors',
            'NumberProcessors', 'IsHyperThreading', 'SystemFamily', 'SystemSkuNumber', 'SystemType', 'IsSystemManagedPageFile', 'TotalPhysicalMemory'
        }

        It "Should return property: <_>" -ForEach $props {
            $result.PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
        }
    }
}

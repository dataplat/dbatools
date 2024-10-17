param($ModuleName = 'dbatools')

Describe "Get-DbaComputerSystem" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaComputerSystem
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have IncludeAws as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeAws -Type switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
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

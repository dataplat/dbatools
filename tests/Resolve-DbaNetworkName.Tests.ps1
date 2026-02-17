#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Resolve-DbaNetworkName",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "Turbo",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Testing basic name resolution" {
        It "should test env:computername" {
            $result = Resolve-DbaNetworkName $env:computername -EnableException -OutVariable "global:dbatoolsciOutput"
            $result.InputName | Should -Be $env:computername
            $result.ComputerName | Should -Be $env:computername
            $result.IPAddress | Should -Not -BeNullOrEmpty
            $result.DNSHostName | Should -Be $env:computername
            if ($result.DNSDomain) {
                $result.FullComputerName | Should -Be ($result.ComputerName + "." + $result.DNSDomain)
            } else {
                $result.FullComputerName | Should -Be $env:computername
            }
        }

        It "should test localhost" {
            $result = Resolve-DbaNetworkName localhost -EnableException
            $result.InputName | Should -Be "localhost"
            $result.ComputerName | Should -Be $env:computername
            $result.IPAddress | Should -Not -BeNullOrEmpty
            $result.DNSHostName | Should -Be $env:computername
            if ($result.DNSDomain) {
                $result.FullComputerName | Should -Be ($result.ComputerName + "." + $result.DNSDomain)
            } else {
                $result.FullComputerName | Should -Be $env:computername
            }
        }

        It "should test 127.0.0.1" {
            $result = Resolve-DbaNetworkName "127.0.0.1" -EnableException
            $result.InputName | Should -Be "127.0.0.1"
            $result.ComputerName | Should -Be $env:computername
            $result.IPAddress | Should -Not -BeNullOrEmpty
            $result.DNSHostName | Should -Be $env:computername
            if ($result.DNSDomain) {
                $result.FullComputerName | Should -Be ($result.ComputerName + "." + $result.DNSDomain)
            } else {
                $result.FullComputerName | Should -Be $env:computername
            }
        }

        It "should test 8.8.8.8 with Turbo = true" -Skip:$true {
            $result = Resolve-DbaNetworkName "8.8.8.8" -EnableException -Turbo:$true
            $result.InputName | Should -Be "8.8.8.8"
            $result.ComputerName | Should -Be "google-public-dns-a"
            $result.IPAddress | Should -Be "8.8.8.8"
            $result.DNSHostName | Should -Be "google-public-dns-a"
            $result.DNSDomain | Should -Be "google.com"
            $result.Domain | Should -Be "google.com"
            $result.DNSHostEntry | Should -Be "google-public-dns-a.google.com"
            $result.FQDN | Should -Be "google-public-dns-a.google.com"
            $result.FullComputerName | Should -Be "8.8.8.8"
        }

        It "should test 8.8.8.8 with Turbo = false" -Skip:$true {
            $result = Resolve-DbaNetworkName "8.8.8.8" -EnableException -Turbo:$false
            $result.InputName | Should -Be "8.8.8.8"
            $result.ComputerName | Should -Be "google-public-dns-a"
            $result.IPAddress | Should -Be "8.8.8.8"
            $result.DNSHostName | Should -Be "google-public-dns-a"
            $result.DNSDomain | Should -Be "google.com"
            $result.Domain | Should -Be "google.com"
            $result.DNSHostEntry | Should -Be "google-public-dns-a.google.com"
            $result.FQDN | Should -Be "google-public-dns-a.google.com"
            $result.FullComputerName | Should -Be "8.8.8.8"
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "InputName",
                "ComputerName",
                "IPAddress",
                "DNSHostname",
                "DNSDomain",
                "Domain",
                "DNSHostEntry",
                "FQDN",
                "FullComputerName"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
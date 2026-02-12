#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaProcess",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Spid",
                "ExcludeSpid",
                "Database",
                "Login",
                "Hostname",
                "Program",
                "ExcludeSystemSpids",
                "EnableException",
                "Intersect"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing Get-DbaProcess results" {
        BeforeAll {
            $allResults = @(Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle)
        }

        It "matches self as a login at least once" {
            $matching = $allResults | Where-Object Login -match $env:USERNAME
            $matching | Should -Not -BeNullOrEmpty
        }

        It "returns only dbatools processes when filtered by Program" {
            $dbatoolsResults = @(Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program "dbatools PowerShell module - dbatools.io")
            foreach ($result in $dbatoolsResults) {
                $result.Program | Should -Be "dbatools PowerShell module - dbatools.io"
            }
        }

        It "returns only processes from master database when filtered by Database" {
            $masterResults = @(Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database master)
            foreach ($result in $masterResults) {
                $result.Database | Should -Be "master"
            }
        }

        It "returns only dbatools processes and master when filtered by Program and Database and told to intersect" {
            $dbatoolsResults = @(Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program "dbatools PowerShell module - dbatools.io" -Database master -Intersect)
            foreach ($result in $dbatoolsResults) {
                $result.Program | Should -Be "dbatools PowerShell module - dbatools.io"
                $result.Database | Should -Be "master"
            }
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle)
        }

        It "Returns output" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "System.Data.DataRow"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Spid",
                "Login",
                "LoginTime",
                "Host",
                "Database",
                "BlockingSpid",
                "Program",
                "Status",
                "Command",
                "Cpu",
                "MemUsage",
                "LastRequestStartTime",
                "LastRequestEndTime",
                "MinutesAsleep",
                "ClientNetAddress",
                "NetTransport",
                "EncryptOption",
                "AuthScheme",
                "NetPacketSize",
                "ClientVersion",
                "HostProcessId",
                "IsSystem",
                "EndpointName",
                "IsDac",
                "LastQuery"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}

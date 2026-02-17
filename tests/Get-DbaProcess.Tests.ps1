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
            $allResults = @(Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput")
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
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.Data.DataRow]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "System\.Data\.DataRow"
        }
    }
}

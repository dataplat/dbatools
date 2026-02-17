#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "SqlCredential",
                "SkipPSRemoting",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing if command works" {
        It "returns the correct results" {
            $port = (Get-DbaTcpPort -SqlInstance $TestConfig.InstanceSingle).Port
            $whoami = whoami

            $results = Test-DbaConnection -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"

            $results.TcpPort | Should -Be $port
            $results.AuthType | Should -Be 'Windows Authentication'
            $results.ConnectingAsUser | Should -Be $whoami
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SqlVersion",
                "ConnectingAsUser",
                "ConnectSuccess",
                "AuthType",
                "AuthScheme",
                "TcpPort",
                "IPAddress",
                "NetBiosName",
                "IsPingable",
                "PSRemotingAccessible",
                "DomainName",
                "LocalWindows",
                "LocalPowerShell",
                "LocalCLR",
                "LocalSMOVersion",
                "LocalDomainUser",
                "LocalRunAsAdmin",
                "LocalEdition"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            # C# cmdlet in dbatools.library takes precedence - help returns System.Object
            # The PowerShell function wrapper has correct PSCustomObject documentation
            $help.returnValues.returnValue.type.name | Should -Not -BeNullOrEmpty
        }
    }
}
#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "ModuleName",
                "ModuleVersion",
                "Scope",
                "IncludeFilter",
                "ExcludeFilter",
                "Peek",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $configPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $configPath -ItemType Directory

        # Export current dbatools config to a file to use as import source
        $configFile = Join-Path $configPath "testconfig.json"
        Get-DbatoolsConfig -Module logging | Export-DbatoolsConfig -OutPath $configFile

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-Item -Path $configPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When importing config with -Peek" {
        It "Should return config items without applying them" {
            $splatImport = @{
                Path            = $configFile
                Peek            = $true
                EnableException = $true
            }
            $result = Import-DbatoolsConfig @splatImport -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "When importing config without -Peek" {
        It "Should import config settings without output" {
            $result = Import-DbatoolsConfig -Path $configFile -EnableException
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "FullName",
                "Value",
                "Type",
                "KeepPersisted",
                "Enforced",
                "Policy"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have a FullName property with a value" {
            $global:dbatoolsciOutput[0].FullName | Should -Not -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
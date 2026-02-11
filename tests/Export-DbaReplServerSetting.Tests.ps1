#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaReplServerSetting",
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
                "Path",
                "FilePath",
                "ScriptOption",
                "InputObject",
                "Encoding",
                "Passthru",
                "NoClobber",
                "Append",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:($env:APPVEYOR) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Must enable distributor first before we can export replication settings
            $distDbName = "dbatoolsci_distrepl_$(Get-Random)"
            $splatDistributor = @{
                SqlInstance          = $TestConfig.InstanceSingle
                DistributionDatabase = $distDbName
                Confirm              = $false
            }
            $null = Enable-DbaReplDistributor @splatDistributor

            $splatPublishing = @{
                SqlInstance = $TestConfig.InstanceSingle
                Confirm     = $false
            }
            $null = Enable-DbaReplPublishing @splatPublishing

            $result = Export-DbaReplServerSetting -SqlInstance $TestConfig.InstanceSingle -Passthru

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -Force -Confirm:$false -ErrorAction SilentlyContinue
            $null = Disable-DbaReplDistributor -SqlInstance $TestConfig.InstanceSingle -Force -Confirm:$false -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output as string when using -Passthru" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [System.String]
        }

        It "Includes the sp_dropdistributor statement" {
            $result -match "sp_dropdistributor" | Should -Not -BeNullOrEmpty
        }

        It "Returns no output when writing to file" {
            $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $tempPath -ItemType Directory
            try {
                $fileResult = Export-DbaReplServerSetting -SqlInstance $TestConfig.InstanceSingle -Path $tempPath
                $fileResult | Should -BeNullOrEmpty
            } finally {
                Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
}
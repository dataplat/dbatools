#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "SqlInstance",
                "Path",
                "SqlCredential",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $spConfigPath = "$($TestConfig.Temp)\dbatoolsci_spconfigure_$(Get-Random).sql"
            $null = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -FilePath $spConfigPath
        }

        AfterAll {
            Remove-Item -Path $spConfigPath -ErrorAction SilentlyContinue
        }

        It "Returns no output" {
            # Some sp_configure options (e.g. 'suppress recovery model errors') are not supported
            # on Express Edition, which generates warnings/errors during import - suppress them
            $outputResult = Import-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Path $spConfigPath -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $outputResult | Should -BeNullOrEmpty
        }
    }
}
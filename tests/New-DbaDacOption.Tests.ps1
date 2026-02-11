#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDacOption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Type",
                "Action",
                "PublishXml",
                "Property",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $publishProfile = New-DbaDacProfile -SqlInstance $TestConfig.InstanceSingle -Database whatever -Path $TestConfig.Temp -EnableException
    }

    AfterAll {
        Remove-Item -Path $publishProfile.FileName -ErrorAction SilentlyContinue
    }

    It "Returns dacpac export options" {
        New-DbaDacOption -Action Export | Should -Not -BeNullOrEmpty
    }

    It "Returns bacpac export options" {
        New-DbaDacOption -Action Export -Type Bacpac | Should -Not -BeNullOrEmpty
    }

    It "Returns dacpac publish options" {
        New-DbaDacOption -Action Publish | Should -Not -BeNullOrEmpty
    }

    It "Returns dacpac publish options from an xml" {
        New-DbaDacOption -Action Publish -PublishXml $publishProfile.FileName -EnableException | Should -Not -BeNullOrEmpty
    }

    It "Returns bacpac publish options" {
        New-DbaDacOption -Action Publish -Type Bacpac | Should -Not -BeNullOrEmpty
    }

    It "Properly sets a property value when specified" {
        (New-DbaDacOption -Action Export -Property @{CommandTimeout = 5 }).CommandTimeout | Should -Be 5
        (New-DbaDacOption -Action Export -Type Bacpac -Property @{CommandTimeout = 5 }).CommandTimeout | Should -Be 5
        (New-DbaDacOption -Action Publish -Property @{GenerateDeploymentReport = $true }).GenerateDeploymentReport | Should -BeTrue
        (New-DbaDacOption -Action Publish -Type Bacpac -Property @{CommandTimeout = 5 }).CommandTimeout | Should -Be 5
        $result = (New-DbaDacOption -Action Publish -Property @{
                GenerateDeploymentReport = $true; DeployOptions = @{CommandTimeout = 5 }
            }
        )
        $result.GenerateDeploymentReport | Should -BeTrue
        $result.DeployOptions.CommandTimeout | Should -Be 5
    }

    Context "Output validation" {
        It "Returns DacExtractOptions for Dacpac Export" {
            $dacpacExport = New-DbaDacOption -Action Export -Type Dacpac
            $dacpacExport | Should -Not -BeNullOrEmpty
            $dacpacExport | Should -BeOfType [Microsoft.SqlServer.Dac.DacExtractOptions]
        }

        It "Returns DacExportOptions for Bacpac Export" {
            $bacpacExport = New-DbaDacOption -Action Export -Type Bacpac
            $bacpacExport | Should -Not -BeNullOrEmpty
            $bacpacExport | Should -BeOfType [Microsoft.SqlServer.Dac.DacExportOptions]
        }

        It "Returns PublishOptions for Dacpac Publish" {
            $dacpacPublish = New-DbaDacOption -Action Publish -Type Dacpac
            $dacpacPublish | Should -Not -BeNullOrEmpty
            $dacpacPublish | Should -BeOfType [Microsoft.SqlServer.Dac.PublishOptions]
        }

        It "Returns DacImportOptions for Bacpac Publish" {
            $bacpacPublish = New-DbaDacOption -Action Publish -Type Bacpac
            $bacpacPublish | Should -Not -BeNullOrEmpty
            $bacpacPublish | Should -BeOfType [Microsoft.SqlServer.Dac.DacImportOptions]
        }
    }
}
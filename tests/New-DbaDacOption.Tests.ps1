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
        New-DbaDacOption -Action Export -OutVariable "global:dbatoolsciOutput" | Should -Not -BeNullOrEmpty
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
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type for Dacpac Export" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Dac.DacExtractOptions]
        }

        It "Should return the correct type for Bacpac Export" {
            $result = New-DbaDacOption -Action Export -Type Bacpac
            $result | Should -BeOfType [Microsoft.SqlServer.Dac.DacExportOptions]
        }

        It "Should return the correct type for Dacpac Publish" {
            $result = New-DbaDacOption -Action Publish
            $result | Should -BeOfType [Microsoft.SqlServer.Dac.PublishOptions]
        }

        It "Should return the correct type for Bacpac Publish" {
            $result = New-DbaDacOption -Action Publish -Type Bacpac
            $result | Should -BeOfType [Microsoft.SqlServer.Dac.DacImportOptions]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $outputTypes = $help.returnValues.returnValue.type.name
            $outputTypes | Should -Match "DacExtractOptions"
            $outputTypes | Should -Match "DacExportOptions"
            $outputTypes | Should -Match "PublishOptions"
            $outputTypes | Should -Match "DacImportOptions"
        }
    }
}
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

    Context "Output Validation - Dacpac Export" {
        BeforeAll {
            $result = New-DbaDacOption -Type Dacpac -Action Export -EnableException
        }

        It "Returns the documented output type DacExtractOptions" {
            $result | Should -BeOfType [Microsoft.SqlServer.Dac.DacExtractOptions]
        }

        It "Has ExtractAllTableData property" {
            $result.PSObject.Properties.Name | Should -Contain 'ExtractAllTableData'
        }

        It "Has CommandTimeout property" {
            $result.PSObject.Properties.Name | Should -Contain 'CommandTimeout'
        }
    }

    Context "Output Validation - Bacpac Export" {
        BeforeAll {
            $result = New-DbaDacOption -Type Bacpac -Action Export -EnableException
        }

        It "Returns the documented output type DacExportOptions" {
            $result | Should -BeOfType [Microsoft.SqlServer.Dac.DacExportOptions]
        }

        It "Has CommandTimeout property" {
            $result.PSObject.Properties.Name | Should -Contain 'CommandTimeout'
        }
    }

    Context "Output Validation - Dacpac Publish" {
        BeforeAll {
            $result = New-DbaDacOption -Type Dacpac -Action Publish -EnableException
        }

        It "Returns the documented output type PublishOptions" {
            $result | Should -BeOfType [Microsoft.SqlServer.Dac.PublishOptions]
        }

        It "Has DeployOptions property" {
            $result.PSObject.Properties.Name | Should -Contain 'DeployOptions'
        }

        It "Has GenerateDeploymentScript property" {
            $result.PSObject.Properties.Name | Should -Contain 'GenerateDeploymentScript'
        }

        It "DeployOptions is of type DacDeployOptions" {
            $result.DeployOptions | Should -BeOfType [Microsoft.SqlServer.Dac.DacDeployOptions]
        }
    }

    Context "Output Validation - Bacpac Publish" {
        BeforeAll {
            $result = New-DbaDacOption -Type Bacpac -Action Publish -EnableException
        }

        It "Returns the documented output type DacImportOptions" {
            $result | Should -BeOfType [Microsoft.SqlServer.Dac.DacImportOptions]
        }

        It "Has CommandTimeout property" {
            $result.PSObject.Properties.Name | Should -Contain 'CommandTimeout'
        }
    }

    Context "Output Validation - PublishXml Profile" {
        BeforeAll {
            $result = New-DbaDacOption -Type Dacpac -Action Publish -PublishXml $publishProfile.FileName -EnableException
        }

        It "Returns PublishOptions when using PublishXml" {
            $result | Should -BeOfType [Microsoft.SqlServer.Dac.PublishOptions]
        }

        It "Loads DeployOptions from profile" {
            $result.DeployOptions | Should -Not -BeNullOrEmpty
            $result.DeployOptions | Should -BeOfType [Microsoft.SqlServer.Dac.DacDeployOptions]
        }
    }
}
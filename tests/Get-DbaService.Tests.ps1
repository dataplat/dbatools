#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaService",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Credential",
                "Type",
                "ServiceName",
                "AdvancedProperties",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName { $null }
            { Get-DbaService -ComputerName "DoesNotExist142" -WarningAction Stop 3> $null } | Should -Throw
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope "dbatools" {
        Context "Type filtering" {
            BeforeAll {
                Mock Resolve-DbaNetworkName {
                    [PSCustomObject]@{
                        FullComputerName = "sql01"
                    }
                }

                Mock Get-DbaReportingService {
                    [PSCustomObject]@{
                        ComputerName = "sql01"
                        ServiceName  = "PowerBIReportServer"
                        ServiceType  = "PowerBI"
                        InstanceName = "PBIRS"
                        DisplayName  = "Power BI Report Server"
                        StartName    = "CONTOSO\\svc-pbirs"
                        State        = "Running"
                        StartMode    = "Automatic"
                    }
                }

                Mock Get-DbaCmObject {
                    param(
                        $ComputerName,
                        $Credential,
                        $Namespace,
                        $ClassName,
                        $Query,
                        $EnableException
                    )

                    if ($Namespace -eq "root\Microsoft" -and $ClassName -eq "__NAMESPACE") {
                        [PSCustomObject]@{
                            Name = "Microsoft"
                        }
                    }
                }

                Mock Select-DefaultView {
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject,
                        $Property,
                        $TypeName
                    )
                    process {
                        $InputObject
                    }
                }
            }

            It "skips SqlService lookups when only PowerBI services are requested" {
                $results = Get-DbaService -ComputerName "sql01" -Type PowerBI

                $results | Should -HaveCount 1
                $results.ServiceType | Should -Be "PowerBI"
                Should -Invoke Get-DbaReportingService -Times 1 -Exactly -Scope It
                Should -Invoke Get-DbaCmObject -Times 0 -Exactly -Scope It -ParameterFilter { $Namespace -eq "root\Microsoft\SQLServer" }
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $instanceName = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).ServiceName
            $allServicesResults = Get-DbaService -ComputerName $TestConfig.InstanceSingle
            $agentServicesResults = Get-DbaService -ComputerName $TestConfig.InstanceSingle -Type Agent
            $specificInstanceResults = Get-DbaService -ComputerName $TestConfig.InstanceSingle -InstanceName $instanceName -Type Agent -AdvancedProperties
        }

        It "shows some services" {
            $allServicesResults.DisplayName | Should -Not -BeNullOrEmpty
        }

        It "shows only one service type" {
            foreach ($result in $agentServicesResults) {
                $result.DisplayName -match "Agent" | Should -Be $true
            }
        }

        It "shows a service from a specific instance" {
            $specificInstanceResults.ServiceType | Should -Be "Agent"
        }

        It "Includes a Clustered Property" {
            $specificInstanceResults.Clustered | Should -Not -BeNullOrEmpty
        }

        It "sets startup mode of the service to 'Manual'" {
            $service = Get-DbaService -ComputerName $TestConfig.InstanceSingle -Type Agent -InstanceName $instanceName
            { $service.ChangeStartMode("Manual") } | Should -Not -Throw
        }

        It "verifies that startup mode of the service is 'Manual'" {
            $results = Get-DbaService -ComputerName $TestConfig.InstanceSingle -Type Agent -InstanceName $instanceName
            $results.StartMode | Should -Be "Manual"
        }

        It "sets startup mode of the service to 'Automatic'" {
            $service = Get-DbaService -ComputerName $TestConfig.InstanceSingle -Type Agent -InstanceName $instanceName
            { $service.ChangeStartMode("Automatic") } | Should -Not -Throw
        }

        It "verifies that startup mode of the service is 'Automatic'" {
            $results = Get-DbaService -ComputerName $TestConfig.InstanceSingle -Type Agent -InstanceName $instanceName
            $results.StartMode | Should -Be "Automatic"
        }
    }

    Context "Command actually works with SqlInstance" {
        BeforeAll {
            $sqlInstanceResults = @()
            $sqlInstanceResults += Get-DbaService -SqlInstance $TestConfig.InstanceSingle -Type Engine
        }

        It "shows exactly one service" {
            $sqlInstanceResults.Count | Should -Be 1
        }
    }
}
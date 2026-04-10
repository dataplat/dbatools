#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Expand-DbaDbLogFile",
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
                "Database",
                "ExcludeDatabase",
                "TargetLogSize",
                "IncrementSize",
                "TargetVlfCount",
                "LogFileId",
                "ShrinkLogFile",
                "ShrinkSize",
                "BackupDirectory",
                "ExcludeDiskSpaceValidation",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "TargetVlfCount planning" {
            BeforeEach {
                $script:appliedSizes = @()
                $script:measureCallCount = 0
                $script:warningMessages = @()

                $script:mockLogFile = [PSCustomObject]@{
                    ID       = 2
                    Name     = "testdb_log"
                    Size     = 80 * 1024
                    FileName = "C:\temp\testdb_log.ldf"
                }
                $script:mockLogFile | Add-Member -MemberType ScriptMethod -Name Alter -Value {
                    $script:appliedSizes += $this.Size
                }
                $script:mockLogFile | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }

                $script:mockDatabase = [PSCustomObject]@{
                    Name          = "testdb"
                    ID            = 42
                    IsAccessible  = $true
                    LogFiles      = @($script:mockLogFile)
                    RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Full
                }

                $script:mockServer = [PSCustomObject]@{
                    ComputerName       = "sql1"
                    ServiceName        = "MSSQLSERVER"
                    DomainInstanceName = "sql1"
                    Name               = "sql1"
                    Version            = [PSCustomObject]@{
                        Major = 12
                    }
                    Databases          = @($script:mockDatabase)
                }

                function Test-FunctionInterrupt {
                    $false
                }
                function Resolve-DbaComputerName {
                    "sql1"
                }
                function Select-DefaultView {
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject
                    )

                    process {
                        $InputObject
                    }
                }
                function Write-Message {
                    param($Level, $Message)

                    if ($Level -eq "Warning") {
                        $script:warningMessages += $Message
                    }
                }
                Mock Connect-DbaInstance {
                    $script:mockServer
                }
                Mock Measure-DbaDbVirtualLogFile {
                    $script:measureCallCount += 1

                    if ($script:measureCallCount -eq 1) {
                        [PSCustomObject]@{
                            Total = 10
                        }
                    } else {
                        [PSCustomObject]@{
                            Total = 15
                        }
                    }
                }
            }

            It "Uses a smaller final growth when that keeps VLFs within TargetVlfCount" {
                $results = Expand-DbaDbLogFile -SqlInstance "sql1" -Database "testdb" -TargetLogSize 150 -TargetVlfCount 15 -ExcludeDiskSpaceValidation

                $results | Should -HaveCount 1
                $script:appliedSizes | Should -HaveCount 2
                $script:appliedSizes[0] | Should -BeGreaterThan (80 * 1024)
                $script:appliedSizes[0] | Should -BeLessThan (150 * 1024)
                $script:appliedSizes[-1] | Should -Be (150 * 1024)
                $script:warningMessages | Should -BeNullOrEmpty
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $db1Name = "dbatoolsci_expand"
        $db1 = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db1Name

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1Name

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Ensure command functionality" {
        BeforeAll {
            $results = Expand-DbaDbLogFile -SqlInstance $TestConfig.InstanceSingle -Database $db1Name -TargetLogSize 128
        }

        It "Should have correct properties" {
            $ExpectedProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseID", "ID", "Name", "LogFileCount", "InitialSize", "CurrentSize", "InitialVLFCount", "CurrentVLFCount"
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should have database name and ID" {
            foreach ($result in $results) {
                $result.Database | Should -Be $db1Name
                $result.DatabaseID | Should -Be $db1.ID
            }
        }

        It "Should have grown the log file" {
            foreach ($result in $results) {
                $result.InitialSize -gt $result.CurrentSize
            }
        }
    }
}
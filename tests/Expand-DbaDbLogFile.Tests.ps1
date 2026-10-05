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
                        $InputObject,
                        $ExcludeProperty
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
                function Measure-DbaDbVirtualLogFile {
                    param($SqlInstance, $Database)

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

    Context "Completes its progress bars" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The bar of the database and the bar of the
            # growth below it used to stay even after a run that worked. The runspace imports the manifest: an
            # import of the psm1 without a command line skips the type data.
            $splatGrowAgain = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Database      = $db1Name
                TargetLogSize = 160
                Confirm       = $false
            }
            if ($TestConfig.SqlCred) {
                $splatGrowAgain.SqlCredential = $TestConfig.SqlCred
            }
            $growRunspace = [runspacefactory]::CreateRunspace()
            $growRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $growRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $growShell = [powershell]::Create()
            $growShell.Runspace = $growRunspace
            $growResult = $growShell.AddCommand("Expand-DbaDbLogFile").AddParameters($splatGrowAgain).Invoke()
            $growRecords = @($growShell.Streams.Progress)
            $growShell.Dispose()
            $growRunspace.Dispose()
        }

        It "Grows the log file" {
            $growResult.Database | Should -Be $db1Name
        }

        It "Completes the bar of the database and the bar of the growth" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $growRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $growRecords | Where-Object Activity -like "Using database: $db1Name*" | Should -Not -BeNullOrEmpty
            $growRecords | Where-Object Activity -like "Growing file*" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}
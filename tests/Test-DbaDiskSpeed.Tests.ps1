#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName   = "dbatools",
    $CommandName = "Test-DbaDiskSpeed",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeAll {
    Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
    $global:TestConfig = Get-TestConfig
}

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
                "EnableException",
                "AggregateBy"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "should have info for model" {
            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1
            $results.FileName -contains "modellog.ldf" | Should -Be $true
        }
        It "returns only for master" {
            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 -Database master
            $results.Count | Should -Be 2
            (($results.FileName -contains "master.mdf") -and ($results.FileName -contains "mastlog.ldf")) | Should -Be $true

            foreach ($result in $results) {
                $result.Reads | Should -BeGreaterOrEqual 0
            }
        }

        # note: if testing the Linux scenarios with instance2 this test should be skipped or change it to a different instance.
        It "sample pipeline" {
            $results = @($TestConfig.instance1, $TestConfig.instance2) | Test-DbaDiskSpeed -Database master
            $results.Count | Should -Be 4

            # for some reason this doesn't work on AppVeyor, perhaps due to the way the instances are started up the instance names do not match the values in Get-TestConfig
            #(($results.SqlInstance -contains $TestConfig.instance1) -and ($results.SqlInstance -contains $TestConfig.instance2)) | Should -Be $true
        }

        It "multiple databases included" {
            $databases = @("master", "model")
            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 -Database $databases
            $results.Count | Should -Be 4
            (($results.Database -contains "master") -and ($results.Database -contains "model")) | Should -Be $true
        }

        It "multiple databases excluded" {
            $excludedDatabases = @("master", "model")
            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 -ExcludeDatabase $excludedDatabases
            $results.Count | Should -BeGreaterOrEqual 1
            (($results.Database -notcontains "master") -and ($results.Database -notcontains "model")) | Should -Be $true
        }

        It "default aggregate by file" {
            $resultsWithParam = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 -AggregateBy "File"
            $resultsWithoutParam = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1

            $resultsWithParam.count | Should -Be $resultsWithoutParam.count
            $resultsWithParam.FileName -contains "modellog.ldf" | Should -Be $true
            $resultsWithoutParam.FileName -contains "modellog.ldf" | Should -Be $true
        }

        It "aggregate by database" {
            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 -AggregateBy "Database"
            #$databases = Get-DbaDatabase -SqlInstance $TestConfig.instance1

            $results.Database -contains "model" | Should -Be $true
            #$results.count                      | Should -Be $databases.count # not working on AppVeyor but works fine locally
        }

        It "aggregate by disk" {
            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 -AggregateBy "Disk"
            (($results -is [System.Data.DataRow]) -or ($results.count -ge 1)) | Should -Be $true
            #($results.SqlInstance -contains $TestConfig.instance1)                  | Should -Be $true
        }

        It "aggregate by file and check column names returned" {
            # check returned columns
            [object[]]$expectedColumnArray = "ComputerName", "InstanceName", "SqlInstance", "Database", "SizeGB", "FileName", "FileID", "FileType", "DiskLocation", "Reads", "AverageReadStall", "ReadPerformance", "Writes", "AverageWriteStall", "WritePerformance", "Avg Overall Latency", "Avg Bytes/Read", "Avg Bytes/Write", "Avg Bytes/Transfer"

            $validColumns = $false

            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 # default usage of command with no params is equivalent to AggregateBy = "File"

            if (($null -ne $results)) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    Write-Message -Level Warning -Message "Unexpected results returned from $($TestConfig.instance1): $($results)"
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $PSItem.Name })

                    if (@(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0) {
                        Write-Message -Level Debug -Message "Columns matched on $($TestConfig.instance1)"
                        $validColumns = $true
                    } else {
                        Write-Message -Level Warning -Message "The columns specified in the expectedColumnArray variable do not match these returned columns from $($TestConfig.instance1): $($columnNamesReturned)"
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        It "aggregate by database and check column names returned" {
            # check returned columns
            [object[]]$expectedColumnArray = "ComputerName", "InstanceName", "SqlInstance", "Database", "DiskLocation", "Reads", "AverageReadStall", "ReadPerformance", "Writes", "AverageWriteStall", "WritePerformance", "Avg Overall Latency", "Avg Bytes/Read", "Avg Bytes/Write", "Avg Bytes/Transfer"

            $validColumns = $false

            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 -AggregateBy "Database"

            if (($null -ne $results)) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    Write-Message -Level Warning -Message "Unexpected results returned from $($TestConfig.instance1): $($results)"
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $PSItem.Name })

                    if (@(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0) {
                        Write-Message -Level Debug -Message "Columns matched on $($TestConfig.instance1)"
                        $validColumns = $true
                    } else {
                        Write-Message -Level Warning -Message "The columns specified in the expectedColumnArray variable do not match these returned columns from $($TestConfig.instance1): $($columnNamesReturned)"
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        It "aggregate by disk and check column names returned" {
            # check returned columns
            [object[]]$expectedColumnArray = "ComputerName", "InstanceName", "SqlInstance", "DiskLocation", "Reads", "AverageReadStall", "ReadPerformance", "Writes", "AverageWriteStall", "WritePerformance", "Avg Overall Latency", "Avg Bytes/Read", "Avg Bytes/Write", "Avg Bytes/Transfer"

            $validColumns = $false

            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance1 -AggregateBy "Disk"

            if (($null -ne $results)) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    Write-Message -Level Warning -Message "Unexpected results returned from $($TestConfig.instance1): $($results)"
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $PSItem.Name })

                    if (@(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0) {
                        Write-Message -Level Debug -Message "Columns matched on $($TestConfig.instance1)"
                        $validColumns = $true
                    } else {
                        Write-Message -Level Warning -Message "The columns specified in the expectedColumnArray variable do not match these returned columns from $($TestConfig.instance1): $($columnNamesReturned)"
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        # Separate test to run against a Linux-hosted SQL instance.
        # To run this test ensure you have specified the instance2 values for a Linux-hosted SQL instance in the Get-TestConfig
        It "test commands on a Linux instance" -Skip {
            # use instance with credential info and run through the 3 variations
            # -Skip to be added when checking in the code
            $linuxSecurePassword = ConvertTo-SecureString -String $TestConfig.instance2SQLPassword -AsPlainText -Force
            $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $TestConfig.instance2SQLUserName, $linuxSecurePassword

            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Database"
            $databases = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -SqlCredential $linuxSqlCredential

            $results.Database -contains "model" | Should -Be $true
            $results.count | Should -Be $databases.count

            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Disk"

            (($results -is [System.Data.DataRow]) -or ($results.count -ge 1)) | Should -Be $true

            $resultsWithParam = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance2 -SqlCredential $linuxSqlCredential -AggregateBy "File"
            $resultsWithoutParam = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance2 -SqlCredential $linuxSqlCredential

            $resultsWithParam.count | Should -Be $resultsWithoutParam.count
            $resultsWithParam.FileName -contains "modellog.ldf" | Should -Be $true
            $resultsWithoutParam.FileName -contains "modellog.ldf" | Should -Be $true
        }

        # Separate test to run against a Linux-hosted SQL instance.
        # To run this test ensure you have specified the instance2 values for a Linux-hosted SQL instance in the Get-TestConfig
        It "aggregate by file and check column names returned on a Linux instance" -Skip {
            # check returned columns
            [object[]]$expectedColumnArray = "ComputerName", "InstanceName", "SqlInstance", "Database", "SizeGB", "FileName", "FileID", "FileType", "DiskLocation", "Reads", "AverageReadStall", "ReadPerformance", "Writes", "AverageWriteStall", "WritePerformance", "Avg Overall Latency", "Avg Bytes/Read", "Avg Bytes/Write", "Avg Bytes/Transfer"

            $validColumns = $false

            $linuxSecurePassword = ConvertTo-SecureString -String $TestConfig.instance2SQLPassword -AsPlainText -Force
            $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $TestConfig.instance2SQLUserName, $linuxSecurePassword

            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance2 -SqlCredential $linuxSqlCredential # default usage of command with no params is equivalent to AggregateBy = "File"

            if (($null -ne $results)) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    Write-Message -Level Warning -Message "Unexpected results returned from $($TestConfig.instance1): $($results)"
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $PSItem.Name })

                    if (@(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0) {
                        Write-Message -Level Debug -Message "Columns matched on $($TestConfig.instance1)"
                        $validColumns = $true
                    } else {
                        Write-Message -Level Warning -Message "The columns specified in the expectedColumnArray variable do not match these returned columns from $($TestConfig.instance1): $($columnNamesReturned)"
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        # Separate test to run against a Linux-hosted SQL instance.
        # To run this test ensure you have specified the instance2 values for a Linux-hosted SQL instance in the Get-TestConfig
        It "aggregate by database and check column names returned on a Linux instance" -Skip {
            # check returned columns
            [object[]]$expectedColumnArray = "ComputerName", "InstanceName", "SqlInstance", "Database", "DiskLocation", "Reads", "AverageReadStall", "ReadPerformance", "Writes", "AverageWriteStall", "WritePerformance", "Avg Overall Latency", "Avg Bytes/Read", "Avg Bytes/Write", "Avg Bytes/Transfer"

            $validColumns = $false

            $linuxSecurePassword = ConvertTo-SecureString -String $TestConfig.instance2SQLPassword -AsPlainText -Force
            $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $TestConfig.instance2SQLUserName, $linuxSecurePassword

            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Database"

            if (($null -ne $results)) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    Write-Message -Level Warning -Message "Unexpected results returned from $($TestConfig.instance1): $($results)"
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $PSItem.Name })

                    if (@(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0) {
                        Write-Message -Level Debug -Message "Columns matched on $($TestConfig.instance1)"
                        $validColumns = $true
                    } else {
                        Write-Message -Level Warning -Message "The columns specified in the expectedColumnArray variable do not match these returned columns from $($TestConfig.instance1): $($columnNamesReturned)"
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        # Separate test to run against a Linux-hosted SQL instance.
        # To run this test ensure you have specified the instance2 values for a Linux-hosted SQL instance in the Get-TestConfig
        It "aggregate by disk and check column names returned on a Linux instance" -Skip {
            # check returned columns
            [object[]]$expectedColumnArray = "ComputerName", "InstanceName", "SqlInstance", "DiskLocation", "Reads", "AverageReadStall", "ReadPerformance", "Writes", "AverageWriteStall", "WritePerformance", "Avg Overall Latency", "Avg Bytes/Read", "Avg Bytes/Write", "Avg Bytes/Transfer"

            $validColumns = $false

            $linuxSecurePassword = ConvertTo-SecureString -String $TestConfig.instance2SQLPassword -AsPlainText -Force
            $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $TestConfig.instance2SQLUserName, $linuxSecurePassword

            $results = Test-DbaDiskSpeed -SqlInstance $TestConfig.instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Disk"

            if (($null -ne $results)) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    Write-Message -Level Warning -Message "Unexpected results returned from $($TestConfig.instance1): $($results)"
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $PSItem.Name })

                    if (@(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0) {
                        Write-Message -Level Debug -Message "Columns matched on $($TestConfig.instance1)"
                        $validColumns = $true
                    } else {
                        Write-Message -Level Warning -Message "The columns specified in the expectedColumnArray variable do not match these returned columns from $($TestConfig.instance1): $($columnNamesReturned)"
                    }
                }
            }

            $validColumns | Should -Be $true
        }
    }
}
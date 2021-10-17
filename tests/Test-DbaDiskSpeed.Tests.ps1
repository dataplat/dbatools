$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
            [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException', 'AggregateBy'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Command actually works" {
        It "should have info for model" {
            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1
            $results.FileName -contains 'modellog.ldf' | Should -Be $true
        }
        It "returns only for master" {
            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 -Database master
            $results.Count | Should -Be 2
            (($results.FileName -contains 'master.mdf') -and ($results.FileName -contains 'mastlog.ldf')) | Should -Be $true

            foreach ($result in $results) {
                $result.Reads | Should -BeGreaterOrEqual 0
            }
        }

        # note: if testing the Linux scenarios with instance2 this test should be skipped or change it to a different instance.
        It "sample pipeline" {
            $results = @($script:instance1, $script:instance2) | Test-DbaDiskSpeed -Database master
            $results.Count | Should -Be 4

            # for some reason this doesn't work on AppVeyor, perhaps due to the way the instances are started up the instance names do not match the values in constants.ps1
            #(($results.SqlInstance -contains $script:instance1) -and ($results.SqlInstance -contains $script:instance2)) | Should -Be $true
        }

        It "multiple databases included" {
            $databases = @('master', 'model')
            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 -Database $databases
            $results.Count | Should -Be 4
            (($results.Database -contains 'master') -and ($results.Database -contains 'model')) | Should -Be $true
        }

        It "multiple databases excluded" {
            $excludedDatabases = @('master', 'model')
            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 -ExcludeDatabase $excludedDatabases
            $results.Count | Should -BeGreaterOrEqual 1
            (($results.Database -notcontains 'master') -and ($results.Database -notcontains 'model')) | Should -Be $true
        }

        It "default aggregate by file" {
            $resultsWithParam = Test-DbaDiskSpeed -SqlInstance $script:instance1 -AggregateBy "File"
            $resultsWithoutParam = Test-DbaDiskSpeed -SqlInstance $script:instance1

            $resultsWithParam.count                                 | Should -Be $resultsWithoutParam.count
            $resultsWithParam.FileName -contains 'modellog.ldf'     | Should -Be $true
            $resultsWithoutParam.FileName -contains 'modellog.ldf'  | Should -Be $true
        }

        It "aggregate by database" {
            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 -AggregateBy "Database"
            #$databases = Get-DbaDatabase -SqlInstance $script:instance1

            $results.Database -contains 'model' | Should -Be $true
            #$results.count                      | Should -Be $databases.count # not working on AppVeyor but works fine locally
        }

        It "aggregate by disk" {
            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 -AggregateBy "Disk"
            (($results -is [System.Data.DataRow]) -or ($results.count -ge 1))   | Should -Be $true
            #($results.SqlInstance -contains $script:instance1)                  | Should -Be $true
        }

        It "aggregate by file and check column names returned" {
            # check returned columns
            [object[]]$expectedColumnArray = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'SizeGB', 'FileName', 'FileID', 'FileType', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $validColumns = $false

            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 # default usage of command with no params is equivalent to AggregateBy = "File"

            if ( ($null -ne $results) ) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        $validColumns = $true
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        It "aggregate by database and check column names returned" {
            # check returned columns
            [object[]]$expectedColumnArray = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $validColumns = $false

            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 -AggregateBy "Database"

            if ( ($null -ne $results) ) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        $validColumns = $true
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        It "aggregate by disk and check column names returned" {
            # check returned columns
            [object[]]$expectedColumnArray = 'ComputerName', 'InstanceName', 'SqlInstance', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $validColumns = $false

            $results = Test-DbaDiskSpeed -SqlInstance $script:instance1 -AggregateBy "Disk"

            if ( ($null -ne $results) ) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        $validColumns = $true
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        # Separate test to run against a Linux-hosted SQL instance.
        # To run this test ensure you have specified the instance2 values for a Linux-hosted SQL instance in the constants.ps1
        It -Skip "test commands on a Linux instance" {
            # use instance with credential info and run through the 3 variations
            # -Skip to be added when checking in the code
            $linuxSecurePassword = ConvertTo-SecureString -String $script:instance2SQLPassword -AsPlainText -Force
            $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $script:instance2SQLUserName, $linuxSecurePassword

            $results = Test-DbaDiskSpeed -SqlInstance $script:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Database"
            $databases = Get-DbaDatabase -SqlInstance $script:instance2 -SqlCredential $linuxSqlCredential

            $results.Database -contains 'model' | Should -Be $true
            $results.count                      | Should -Be $databases.count

            $results = Test-DbaDiskSpeed -SqlInstance $script:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Disk"

            (($results -is [System.Data.DataRow]) -or ($results.count -ge 1))   | Should -Be $true

            $resultsWithParam = Test-DbaDiskSpeed -SqlInstance $script:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "File"
            $resultsWithoutParam = Test-DbaDiskSpeed -SqlInstance $script:instance2 -SqlCredential $linuxSqlCredential

            $resultsWithParam.count                                 | Should -Be $resultsWithoutParam.count
            $resultsWithParam.FileName -contains 'modellog.ldf'     | Should -Be $true
            $resultsWithoutParam.FileName -contains 'modellog.ldf'  | Should -Be $true
        }

        # Separate test to run against a Linux-hosted SQL instance.
        # To run this test ensure you have specified the instance2 values for a Linux-hosted SQL instance in the constants.ps1
        It -Skip "aggregate by file and check column names returned on a Linux instance" {
            # check returned columns
            [object[]]$expectedColumnArray = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'SizeGB', 'FileName', 'FileID', 'FileType', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $validColumns = $false

            $linuxSecurePassword = ConvertTo-SecureString -String $script:instance2SQLPassword -AsPlainText -Force
            $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $script:instance2SQLUserName, $linuxSecurePassword

            $results = Test-DbaDiskSpeed -SqlInstance $script:instance2 -SqlCredential $linuxSqlCredential # default usage of command with no params is equivalent to AggregateBy = "File"

            if ( ($null -ne $results) ) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        $validColumns = $true
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        # Separate test to run against a Linux-hosted SQL instance.
        # To run this test ensure you have specified the instance2 values for a Linux-hosted SQL instance in the constants.ps1
        It -Skip "aggregate by database and check column names returned on a Linux instance" {
            # check returned columns
            [object[]]$expectedColumnArray = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $validColumns = $false

            $linuxSecurePassword = ConvertTo-SecureString -String $script:instance2SQLPassword -AsPlainText -Force
            $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $script:instance2SQLUserName, $linuxSecurePassword

            $results = Test-DbaDiskSpeed -SqlInstance $script:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Database"

            if ( ($null -ne $results) ) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        $validColumns = $true
                    }
                }
            }

            $validColumns | Should -Be $true
        }

        # Separate test to run against a Linux-hosted SQL instance.
        # To run this test ensure you have specified the instance2 values for a Linux-hosted SQL instance in the constants.ps1
        It -Skip "aggregate by disk and check column names returned on a Linux instance" {
            # check returned columns
            [object[]]$expectedColumnArray = 'ComputerName', 'InstanceName', 'SqlInstance', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $validColumns = $false

            $linuxSecurePassword = ConvertTo-SecureString -String $script:instance2SQLPassword -AsPlainText -Force
            $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $script:instance2SQLUserName, $linuxSecurePassword

            $results = Test-DbaDiskSpeed -SqlInstance $script:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Disk"

            if ( ($null -ne $results) ) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    $validColumns = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        $validColumns = $true
                    }
                }
            }

            $validColumns | Should -Be $true
        }
    }
}
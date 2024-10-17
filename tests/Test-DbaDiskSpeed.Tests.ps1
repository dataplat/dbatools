param($ModuleName = 'dbatools')

Describe "Test-DbaDiskSpeed Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDiskSpeed
        }
        It "Should have SqlInstance as a non-mandatory DbaInstanceParameter[] parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a non-mandatory Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have AggregateBy as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter AggregateBy -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "Test-DbaDiskSpeed Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command actually works" {
        It "should have info for model" {
            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1
            $results.FileName | Should -Contain 'modellog.ldf'
        }

        It "returns only for master" {
            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1 -Database master
            $results | Should -HaveCount 2
            $results.FileName | Should -Contain 'master.mdf'
            $results.FileName | Should -Contain 'mastlog.ldf'

            foreach ($result in $results) {
                $result.Reads | Should -BeGreaterOrEqual 0
            }
        }

        It "sample pipeline" {
            $results = @($env:instance1, $env:instance2) | Test-DbaDiskSpeed -Database master
            $results | Should -HaveCount 4
        }

        It "multiple databases included" {
            $databases = @('master', 'model')
            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1 -Database $databases
            $results | Should -HaveCount 4
            $results.Database | Should -Contain 'master'
            $results.Database | Should -Contain 'model'
        }

        It "multiple databases excluded" {
            $excludedDatabases = @('master', 'model')
            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1 -ExcludeDatabase $excludedDatabases
            $results | Should -Not -BeNullOrEmpty
            $results.Database | Should -Not -Contain 'master'
            $results.Database | Should -Not -Contain 'model'
        }

        It "default aggregate by file" {
            $resultsWithParam = Test-DbaDiskSpeed -SqlInstance $env:instance1 -AggregateBy "File"
            $resultsWithoutParam = Test-DbaDiskSpeed -SqlInstance $env:instance1

            $resultsWithParam | Should -HaveCount $resultsWithoutParam.Count
            $resultsWithParam.FileName | Should -Contain 'modellog.ldf'
            $resultsWithoutParam.FileName | Should -Contain 'modellog.ldf'
        }

        It "aggregate by database" {
            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1 -AggregateBy "Database"
            $results.Database | Should -Contain 'model'
        }

        It "aggregate by disk" {
            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1 -AggregateBy "Disk"
            $results | Should -Not -BeNullOrEmpty
        }

        It "aggregate by file and check column names returned" {
            $expectedColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'SizeGB', 'FileName', 'FileID', 'FileType', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1

            $results | Should -Not -BeNullOrEmpty
            $columnNames = $results[0].PSObject.Properties.Name
            $columnNames | Should -Be $expectedColumns
        }

        It "aggregate by database and check column names returned" {
            $expectedColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1 -AggregateBy "Database"

            $results | Should -Not -BeNullOrEmpty
            $columnNames = $results[0].PSObject.Properties.Name
            $columnNames | Should -Be $expectedColumns
        }

        It "aggregate by disk and check column names returned" {
            $expectedColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $results = Test-DbaDiskSpeed -SqlInstance $env:instance1 -AggregateBy "Disk"

            $results | Should -Not -BeNullOrEmpty
            $columnNames = $results[0].PSObject.Properties.Name
            $columnNames | Should -Be $expectedColumns
        }
    }
}

Describe "Test-DbaDiskSpeed Linux Integration Tests" -Tag "LinuxIntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $linuxSecurePassword = ConvertTo-SecureString -String $env:instance2SQLPassword -AsPlainText -Force
        $linuxSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:instance2SQLUserName, $linuxSecurePassword
    }

    Context "Linux instance tests" -Skip:(-not $env:TEST_LINUX_INSTANCE) {
        It "test commands on a Linux instance" {
            $results = Test-DbaDiskSpeed -SqlInstance $env:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Database"
            $databases = Get-DbaDatabase -SqlInstance $env:instance2 -SqlCredential $linuxSqlCredential

            $results.Database | Should -Contain 'model'
            $results | Should -HaveCount $databases.Count

            $results = Test-DbaDiskSpeed -SqlInstance $env:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Disk"
            $results | Should -Not -BeNullOrEmpty

            $resultsWithParam = Test-DbaDiskSpeed -SqlInstance $env:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "File"
            $resultsWithoutParam = Test-DbaDiskSpeed -SqlInstance $env:instance2 -SqlCredential $linuxSqlCredential

            $resultsWithParam | Should -HaveCount $resultsWithoutParam.Count
            $resultsWithParam.FileName | Should -Contain 'modellog.ldf'
            $resultsWithoutParam.FileName | Should -Contain 'modellog.ldf'
        }

        It "aggregate by file and check column names returned on a Linux instance" {
            $expectedColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'SizeGB', 'FileName', 'FileID', 'FileType', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $results = Test-DbaDiskSpeed -SqlInstance $env:instance2 -SqlCredential $linuxSqlCredential

            $results | Should -Not -BeNullOrEmpty
            $columnNames = $results[0].PSObject.Properties.Name
            $columnNames | Should -Be $expectedColumns
        }

        It "aggregate by database and check column names returned on a Linux instance" {
            $expectedColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $results = Test-DbaDiskSpeed -SqlInstance $env:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Database"

            $results | Should -Not -BeNullOrEmpty
            $columnNames = $results[0].PSObject.Properties.Name
            $columnNames | Should -Be $expectedColumns
        }

        It "aggregate by disk and check column names returned on a Linux instance" {
            $expectedColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'DiskLocation', 'Reads', 'AverageReadStall', 'ReadPerformance', 'Writes', 'AverageWriteStall', 'WritePerformance', 'Avg Overall Latency', 'Avg Bytes/Read', 'Avg Bytes/Write', 'Avg Bytes/Transfer'

            $results = Test-DbaDiskSpeed -SqlInstance $env:instance2 -SqlCredential $linuxSqlCredential -AggregateBy "Disk"

            $results | Should -Not -BeNullOrEmpty
            $columnNames = $results[0].PSObject.Properties.Name
            $columnNames | Should -Be $expectedColumns
        }
    }
}

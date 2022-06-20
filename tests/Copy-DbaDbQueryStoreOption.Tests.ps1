$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'SourceDatabase', 'Destination', 'DestinationSqlCredential', 'DestinationDatabase', 'Exclude', 'AllDatabases', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying query store options are copied" {
        BeforeAll {
            $instance2 = Connect-DbaInstance -SqlInstance $script:instance2
        }
        BeforeEach {
            $db1Name = "dbatoolsci_querystoretest1"
            $db1 = New-DbaDatabase -SqlInstance $instance2 -Name $db1Name

            $db1QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $instance2 -Database $db1Name
            $originalQSOptionValue = $db1QSOptions.DataFlushIntervalInSeconds
            $updatedQSOption = $db1QSOptions.DataFlushIntervalInSeconds + 1
            $updatedDB1Options = Set-DbaDbQueryStoreOption -SqlInstance $instance2 -Database $db1Name -FlushInterval $updatedQSOption -State ReadWrite

            $db2Name = "dbatoolsci_querystoretest2"
            $db2 = New-DbaDatabase -SqlInstance $instance2 -Name $db2Name

            $db3Name = "dbatoolsci_querystoretest3"
            $db3 = New-DbaDatabase -SqlInstance $instance2 -Name $db3Name

            $db4Name = "dbatoolsci_querystoretest4"
            $db4 = New-DbaDatabase -SqlInstance $instance2 -Name $db4Name
        }
        AfterEach {
            $db1, $db2, $db3, $db4 | Remove-DbaDatabase -Confirm:$false
        }

        It "Copy the query store options from one db to another on the same instance" {
            $db2QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $instance2 -Database $db2Name
            $db2QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue

            $result = Copy-DbaDbQueryStoreOption -Source $instance2 -SourceDatabase $db1Name -Destination $instance2 -DestinationDatabase $db2Name

            $result.Status | Should -Be Successful
            $result.SourceDatabase | Should -Be $db1Name
            $result.SourceDatabaseID | Should -Be $db1.ID
            $result.Name | Should -Be $db2Name
            $result.DestinationDatabaseID | Should -Be $db2.ID

            $db2QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $instance2 -Database $db2Name
            $db2QSOptions.DataFlushIntervalInSeconds | Should -Be ($originalQSOptionValue + 1)
        }

        It "Apply to all databases except db4" {
            $db3QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $instance2 -Database $db3Name
            $db3QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue

            $result = Copy-DbaDbQueryStoreOption -Source $instance2 -SourceDatabase $db1Name -Destination $instance2 -Exclude $db4Name

            ($result | Where-Object { $_.Status -eq 'Successful' }).Count | Should -Be 3
            ($result | Where-Object { $_.SourceDatabase -eq $db1Name }).Count | Should -Be 3
            ($result | Where-Object { $_.SourceDatabaseID -eq $db1.ID }).Count | Should -Be 3
            $result.Name | Should -Be $db1Name, $db2Name, $db3Name
            $result.DestinationDatabaseID | Should -Be $db1.ID, $db2.ID, $db3.ID

            $dbQSOptions = Get-DbaDbQueryStoreOption -SqlInstance $instance2 -Database $db1Name, $db2Name, $db3Name
            ($dbQSOptions | Where-Object { $_.DataFlushIntervalInSeconds -eq ($originalQSOptionValue + 1) }).Count | Should -Be 3

            $db4QSOptions = Get-DbaDbQueryStoreOption -SqlInstance $instance2 -Database $db4Name
            $db4QSOptions.DataFlushIntervalInSeconds | Should -Be $originalQSOptionValue
        }
    }
}
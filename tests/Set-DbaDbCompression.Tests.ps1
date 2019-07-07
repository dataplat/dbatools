$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'CompressionType', 'MaxRunTime', 'PercentCompression', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("select * into syscols from sys.all_columns
                                select * into sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)", $dbname)
    }
    AfterAll {
        Get-DbaProcess -SqlInstance $script:instance2 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
    }
    $InputObject = Test-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname
    $results = Set-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -MaxRunTime 5 -PercentCompression 0
    Context "Command gets results" {
        It "Should contain objects" {
            $results | Should Not Be $null
        }
    }

    Context "Command handles heaps and clustered indexes" {
        foreach ($row in $results | Where-Object {$_.IndexId -le 1}) {
            It "Should process object $($row.TableName)" {
                $row.AlreadyProcessed | Should Be $True
            }
        }
    }
    Context "Command handles nonclustered indexes" {
        foreach ($row in $results | Where-Object {$_.IndexId -gt 1}) {
            It "Should process nonclustered index $($row.IndexName)" {
                $row.AlreadyProcessed | Should Be $True
            }
        }
    }
    Context "Command excludes results for specified database" {
        $server.Databases[$dbname].Tables['syscols'].PhysicalPartitions[0].DataCompression = "NONE"
        $server.Databases[$dbname].Tables['syscols'].Rebuild()
        It "Shouldn't get any results for $dbname" {
            $(Set-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -ExcludeDatabase $dbname -MaxRunTime 5 -PercentCompression 0).Database | Should not Match $dbname
        }
    }
    Context "Command can accept InputObject from Test-DbaDbCompression" {
        $results = @(Set-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -MaxRunTime 5 -PercentCompression 0 -InputObject $InputObject)
        It "Should get results" {
            $results | Should not be $null
        }
        foreach ($row in $results) {
            It "Should process object $($row.TableName) from InputObject" {
                $row.AlreadyProcessed | Should Be $True
            }
        }
    }
    Context "Command sets compression to Row all objects" {
        $null = Set-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -CompressionType Row
        $results = Get-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname
        foreach ($row in $results) {
            It "The $($row.IndexType) for $($row.schema).$($row.TableName) is row compressed" {
                $row.DataCompression | Should Be "Row"
            }
        }
    }
    Context "Command sets compression to Page for all objects" {
        $null = Set-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -CompressionType Page
        $results = Get-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname
        foreach ($row in $results) {
            It "The $($row.IndexType) for $($row.schema).$($row.TableName) is page compressed" {
                $row.DataCompression | Should Be "Page"
            }
        }
    }
    Context "Command sets compression to None for all objects" {
        $null = Set-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -CompressionType None
        $results = Get-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname
        foreach ($row in $results) {
            It "The $($row.IndexType) for $($row.schema).$($row.TableName) is not compressed" {
                $row.DataCompression | Should Be "None"
            }
        }
    }
}
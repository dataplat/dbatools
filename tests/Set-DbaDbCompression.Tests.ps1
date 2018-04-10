$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 9
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Set-DbaDbCompression).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential','Database','ExcludeDatabase','CompressionType','MaxRunTime','PercentCompression','InputObject','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)",$dbname)
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
        foreach ($row in $results | Where-Object {$_.IndexId -le 1}){
            It "Should process object $($row.TableName)" {
                $row.AlreadyProcesssed | Should Be $True
            }
        }
    }
    Context "Command handles nonclustered indexes" {
        foreach ($row in $results | Where-Object {$_.IndexId -gt 1}){
            It "Should process nonclustered index $($row.IndexName)" {
                $row.AlreadyProcesssed | Should Be $True
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
                $row.AlreadyProcesssed | Should Be $True
            }
        }
    }
}

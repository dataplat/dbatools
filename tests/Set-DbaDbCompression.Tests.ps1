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
        Get-DbaProcess -SqlInstance $script:instance1 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("select * into syscols from sys.all_columns
                                select * into sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)",$dbname)
       }
    AfterAll {
        Get-DbaProcess -SqlInstance $script:instance1 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }
    $InputObject = Test-DbaDbCompression -SqlInstance $script:instance1 -Database $dbname
    $results = Set-DbaDbCompression -SqlInstance $script:instance1 -Database $dbname -MaxRunTime 5 -PercentCompression 0
    Context "Command handles heaps and clustered indexes" {
        @($results | Where-Object {$_.IndexId -le 1}).Foreach{
            It "Should process object $($PSItem.TableName)" {
                $PSItem.AlreadyProcesssed | Should Be $True
            }
        }
    }
    Context "Command handles nonclustered indexes" {
        @($results | Where-Object {$_.IndexId -gt 1}).Foreach{
            It "Should process nonclustered index $($PSItem.IndexName)" {
                $PSItem.AlreadyProcesssed | Should Be $True
            }
        }
    }
    Context "Command excludes results for specified database" {
        $server.Databases[$dbname].Tables['syscols'].PhysicalPartitions[0].DataCompression = "NONE"
        $server.Databases[$dbname].Tables['syscols'].Rebuild()
        It "Shouldn't get any results for $dbname" {
            $(Set-DbaDbCompression -SqlInstance $script:instance1 -Database $dbname -ExcludeDatabase $dbname -MaxRunTime 5 -PercentCompression 0).Database | Should not Match $dbname
        }
    }
    Context "Command can accept InputObject from Test-DbaDbCompression" {
        $results = @(Set-DbaDbCompression -SqlInstance $script:instance1 -Database $dbname -MaxRunTime 5 -PercentCompression 0 -InputObject $InputObject)
        It "Should get results" {
            $results | Should not be $null
        }
        $results.Foreach{
            It "Should process object $($PSItem.TableName) from InputObject" {
                $PSItem.AlreadyProcesssed | Should Be $True
            }
        }
    }
}

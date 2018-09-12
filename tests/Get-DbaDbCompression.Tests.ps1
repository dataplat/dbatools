$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaDbCompression).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential','Database','ExcludeDatabase','EnableException'
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
    $results = Get-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname

    Context "Command handles heaps and clustered indexes" {
        It "Gets results" {
            $results | Should Not Be $null
        }
        Foreach ($row in $results | Where-Object {$_.IndexId -le 1}) {
            It "Should return compression level for object $($row.TableName)" {
                $row.DataCompression | Should BeIn ('None','Row','Page')
            }
        }
    }
    Context "Command handles nonclustered indexes" {
        It "Gets results" {
            $results | Should Not Be $null
        }
        Foreach ($row in $results | Where-Object {$_.IndexId -gt 1}) {
            It "Should return compression level for nonclustered index $($row.IndexName)" {
                $row.DataCompression | Should BeIn ('None','Row','Page')
            }
        }
    }

    Context "Command excludes results for specified database" {
        It "Shouldn't get any results for $dbname" {
            $(Get-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -ExcludeDatabase $dbname) | Should not Match $dbname
        }
    }
}

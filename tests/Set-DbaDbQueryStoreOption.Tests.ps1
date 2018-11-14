$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 13
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Set-DbaDbQueryStoreOption).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'AllDatabases', 'State', 'FlushInterval', 'CollectionInterval', 'MaxSize', 'CaptureMode', 'CleanupMode', 'StaleQueryThreshold', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        Get-DbaDatabase -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -Match 'dbatoolsci' | Remove-DbaDatabase -Confirm:$false
    }
    Context "Get some client protocols" {
        foreach ($instance in ($script:instance1, $script:instance2)) {
            $server = Connect-DbaInstance -SqlInstance $instance
            $results = Get-DbaDbQueryStoreOption -SqlInstance $instance -WarningVariable warning  3>&1

            if ($server.VersionMajor -lt 13) {
                It "should warn" {
                    $warning | Should Not Be $null
                }
            } else {
                It "should return some valid results" {
                    $result = $results | Where-Object Database -eq msdb
                    $result.ActualState | Should Be 'Off'
                    $result.MaxStorageSizeInMB | Should BeGreaterThan 1
                }

                $newnumber = $result.DataFlushIntervalInSeconds + 1

                It "should change the specified param to the new value" {
                    $results = Set-DbaDbQueryStoreOption -SqlInstance $instance -Database msdb -FlushInterval $newnumber -State ReadWrite
                    $results.DataFlushIntervalInSeconds | Should Be $newnumber
                }

                It "should only get one database" {
                    $results = Get-DbaDbQueryStoreOption -SqlInstance $instance -Database model
                    $results.Count | Should Be 1
                    $results.Database | Should Be 'model'
                }

                It "should not get this one database" {
                    $results = Get-DbaDbQueryStoreOption -SqlInstance $instance -ExcludeDatabase model
                    $result = $results | Where-Object Database -eq model
                    $result.Count | Should Be 0
                }
            }
        }
    }
}
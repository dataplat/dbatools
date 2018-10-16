$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 15
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Read-DbaTraceFile).Parameters.Keys
        $knownParameters = 'SqlInstance','SqlCredential','Path','Database','Login','Spid','EventClass','ObjectType','Error','EventSequence','TextData','ApplicationName','ObjectName','Where','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $configs = $script:instance1, $script:instance2 | Get-DbaSpConfigure -ConfigName DefaultTraceEnabled
        $configs | Set-DbaSpConfigure -Value $true -WarningAction SilentlyContinue
    }
    AfterAll {
        foreach ($config in $configs) {
            if (-not $config.DefaultTraceEnabled) {
                $config | Set-DbaSpConfigure -Value $false -WarningAction SilentlyContinue
            }
        }
    }

    Context "Verifying command output" {
        It "returns results" {
            $results = $script:instance1, $script:instance2 | Get-DbaTrace -Id 1 | Read-DbaTraceFile

            $results.DatabaseName.Count | Should -BeGreaterThan 0
        }

        It "supports where for multiple servers" {
            $where = "DatabaseName is not NULL
                    and DatabaseName != 'tempdb'
                    and ApplicationName != 'SQLServerCEIP'
                    and ApplicationName != 'Report Server'
                    and ApplicationName not like 'dbatools%'
                    and ApplicationName not like 'SQLAgent%'
                    and ApplicationName not like 'Microsoft SQL Server Management Studio%'"

            # Collect the results into a variable so that the bulk import is supafast
            $results = $script:instance1, $script:instance2 | Get-DbaTrace -Id 1 | Read-DbaTraceFile -Where $where -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Be $null
        }
    }
}
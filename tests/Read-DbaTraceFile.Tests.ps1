$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'Database', 'Login', 'Spid', 'EventClass', 'ObjectType', 'ErrorId', 'EventSequence', 'TextData', 'ApplicationName', 'ObjectName', 'Where', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $configs = $script:instance1, $script:instance2 | Get-DbaSpConfigure -Name DefaultTraceEnabled
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
            $results = Get-DbaTrace -SqlInstance $script:instance2 -Id 1 | Read-DbaTraceFile
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

            # Collect the results into a variable so that the bulk import is super fast
            Get-DbaTrace -SqlInstance $script:instance2 -Id 1 | Read-DbaTraceFile -Where $where -WarningAction SilentlyContinue -WarningVariable warn > $null
            $warn | Should -Be $null
        }
    }
    Context "Verify Parameter Use" {
        It "Should execute using parameters Database, Login, Spid" {
            $results = Get-DbaTrace -SqlInstance $script:instance2 -Id 1 | Read-DbaTraceFile -Database Master -Login sa -Spid 7 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Be $null
        }
        It "Should execute using parameters EventClass, ObjectType, ErrorId" {
            $results = Get-DbaTrace -SqlInstance $script:instance2 -Id 1 | Read-DbaTraceFile -EventClass 4 -ObjectType 4 -ErrorId 4 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Be $null
        }
        It "Should execute using parameters EventSequence, TextData, ApplicationName, ObjectName" {
            $results = Get-DbaTrace -SqlInstance $script:instance2 -Id 1 | Read-DbaTraceFile -EventSequence 4 -TextData "Text" -ApplicationName "Application" -ObjectName "Name" -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Be $null
        }
    }
}
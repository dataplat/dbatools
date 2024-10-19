param($ModuleName = 'dbatools')

Describe "Read-DbaTraceFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $configs = $global:instance1, $global:instance2 | Get-DbaSpConfigure -Name DefaultTraceEnabled
        $configs | Set-DbaSpConfigure -Value $true -WarningAction SilentlyContinue
    }

    AfterAll {
        foreach ($config in $configs) {
            if (-not $config.DefaultTraceEnabled) {
                $config | Set-DbaSpConfigure -Value $false -WarningAction SilentlyContinue
            }
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Read-DbaTraceFile
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "Database",
                "Login",
                "Spid",
                "EventClass",
                "ObjectType",
                "ErrorId",
                "EventSequence",
                "TextData",
                "ApplicationName",
                "ObjectName",
                "Where",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Verifying command output" {
        It "returns results" {
            $results = Get-DbaTrace -SqlInstance $global:instance2 -Id 1 | Read-DbaTraceFile
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
            $warn = $null
            Get-DbaTrace -SqlInstance $global:instance2 -Id 1 | Read-DbaTraceFile -Where $where -WarningAction SilentlyContinue -WarningVariable warn > $null
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "Verify Parameter Use" {
        It "Should execute using parameters Database, Login, Spid" {
            $warn = $null
            $results = Get-DbaTrace -SqlInstance $global:instance2 -Id 1 | Read-DbaTraceFile -Database Master -Login sa -Spid 7 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -BeNullOrEmpty
        }
        It "Should execute using parameters EventClass, ObjectType, ErrorId" {
            $warn = $null
            $results = Get-DbaTrace -SqlInstance $global:instance2 -Id 1 | Read-DbaTraceFile -EventClass 4 -ObjectType 4 -ErrorId 4 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -BeNullOrEmpty
        }
        It "Should execute using parameters EventSequence, TextData, ApplicationName, ObjectName" {
            $warn = $null
            $results = Get-DbaTrace -SqlInstance $global:instance2 -Id 1 | Read-DbaTraceFile -EventSequence 4 -TextData "Text" -ApplicationName "Application" -ObjectName "Name" -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -BeNullOrEmpty
        }
    }
}

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
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String[]
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[]
        }
        It "Should have Login parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type System.String[]
        }
        It "Should have Spid parameter" {
            $CommandUnderTest | Should -HaveParameter Spid -Type System.Int32[]
        }
        It "Should have EventClass parameter" {
            $CommandUnderTest | Should -HaveParameter EventClass -Type System.String[]
        }
        It "Should have ObjectType parameter" {
            $CommandUnderTest | Should -HaveParameter ObjectType -Type System.String[]
        }
        It "Should have ErrorId parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorId -Type System.Int32[]
        }
        It "Should have EventSequence parameter" {
            $CommandUnderTest | Should -HaveParameter EventSequence -Type System.Int32[]
        }
        It "Should have TextData parameter" {
            $CommandUnderTest | Should -HaveParameter TextData -Type System.String[]
        }
        It "Should have ApplicationName parameter" {
            $CommandUnderTest | Should -HaveParameter ApplicationName -Type System.String[]
        }
        It "Should have ObjectName parameter" {
            $CommandUnderTest | Should -HaveParameter ObjectName -Type System.String[]
        }
        It "Should have Where parameter" {
            $CommandUnderTest | Should -HaveParameter Where -Type System.String
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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

param($ModuleName = 'dbatools')

Describe "Export-DbaScript" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaScript
        }

        It "has all the required parameters" {
            $params = @(
                "InputObject",
                "ScriptingOptionsObject",
                "Path",
                "FilePath",
                "Encoding",
                "BatchSeparator",
                "NoPrefix",
                "Passthru",
                "NoClobber",
                "Append",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
        }

        It "should export some text matching create table" {
            $results = Get-DbaDbTable -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results | Should -Match "CREATE TABLE"
        }

        It "should include BatchSeparator based on the Formatting.BatchSeparator configuration" {
            $results = Get-DbaDbTable -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results | Should -Match "(Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator')"
        }

        It "should include the defined BatchSeparator" {
            $results = Get-DbaDbTable -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $results | Should -Match "MakeItSo"
        }

        It "should not accept non-SMO objects" {
            $null = Get-DbaDbTable -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $null = [pscustomobject]@{ Invalid = $true } | Export-DbaScript -WarningVariable invalid -WarningAction Continue
            $invalid | Should -Match "not a SQL Management Object"
        }

        It "should not append when using NoPrefix (#7455)" {
            BeforeAll {
                if (-not (Test-Path C:\temp)) { $null = New-Item -ItemType Directory -Path C:\temp }
                $null = Get-DbaDbTable -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath C:\temp\msdb.txt
                $linecount1 = (Get-Content C:\temp\msdb.txt).Count
                $null = Get-DbaDbTable -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath C:\temp\msdb.txt
                $linecount2 = (Get-Content C:\temp\msdb.txt).Count
                $null = Get-DbaDbTable -SqlInstance $global:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -NoPrefix -FilePath C:\temp\msdb.txt -Append
                $linecount3 = (Get-Content C:\temp\msdb.txt).Count
            }

            It "Should have the same line count for non-append operations" {
                $linecount1 | Should -Be $linecount2
            }

            It "Should have a different line count when appending" {
                $linecount1 | Should -Not -Be $linecount3
            }
        }
    }
}

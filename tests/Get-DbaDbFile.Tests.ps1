param($ModuleName = 'dbatools')

Describe "Get-DbaDbFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbFile
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have FileGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileGroup -Type Object[] -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Ensure array" {
        BeforeAll {
            $results = Get-Command -Name Get-DbaDbFile | Select-Object -ExpandProperty ScriptBlock
        }
        It "returns disks as an array" {
            $results -match '\$disks \= \@\(' | Should -Be $true
        }
    }

    Context "Should return file information" {
        BeforeAll {
            $results = Get-DbaDbFile -SqlInstance $global:instance1
        }
        It "returns information about tempdb files" {
            $results.Database -contains "tempdb" | Should -Be $true
        }
    }

    Context "Should return file information for only tempdb" {
        BeforeAll {
            $results = Get-DbaDbFile -SqlInstance $global:instance1 -Database tempdb
        }
        It "returns only tempdb files" {
            $results | ForEach-Object {
                $_.Database | Should -Be "tempdb"
            }
        }
    }

    Context "Should return file information for only tempdb primary filegroup" {
        BeforeAll {
            $results = Get-DbaDbFile -SqlInstance $global:instance1 -Database tempdb -FileGroup Primary
        }
        It "returns only tempdb files that are in Primary filegroup" {
            $results | ForEach-Object {
                $_.Database | Should -Be "tempdb"
                $_.FileGroupName | Should -Be "Primary"
            }
        }
    }

    Context "Physical name is populated" {
        BeforeAll {
            $results = Get-DbaDbFile -SqlInstance $global:instance1 -Database master
        }
        It "master returns proper results" {
            $result = $results | Where-Object LogicalName -eq 'master'
            $result.PhysicalName -match 'master.mdf' | Should -Be $true
            $result = $results | Where-Object LogicalName -eq 'mastlog'
            $result.PhysicalName -match 'mastlog.ldf' | Should -Be $true
        }
    }

    Context "Database ID is populated" {
        It "returns proper results for the master db" {
            $results = Get-DbaDbFile -SqlInstance $global:instance1 -Database master
            $results.DatabaseID | Get-Unique | Should -Be (Get-DbaDatabase -SqlInstance $global:instance1 -Database master).ID
        }
        It "uses a pipeline input and returns proper results for the tempdb" {
            $tempDB = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
            $results = $tempDB | Get-DbaDbFile
            $results.DatabaseID | Get-Unique | Should -Be $tempDB.ID
        }
    }
}

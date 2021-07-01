$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Get-DirectoryRestoreFile.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ObjectName'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    Context "Test one part names" {
        It "Should return correct parts" {
            $input = 'table1', '[table2]', '[tab..le3]', '[table]]x4]', '[table5]]]'
            $table = 'table1', 'table2', 'tab..le3', 'table]]x4', 'table5]]'
            for ($i = 0; $i -lt $input.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $input[$i]
                $result.Parsed | Should Be $true
                $result.Database | Should Be $null
                $result.Schema | Should Be $null
                $result.Name | Should Be $table[$i]
            }
        }
    }
    Context "Test two part names" {
        It "Should return correct parts" {
            $input = 'schema1.table1', '[sche..ma2].[table2]', 'schema3.[tab..le3]', '[schema4].[table]]x4]', 'schema5.[table5]]]'
            $table = 'table1', 'table2', 'tab..le3', 'table]]x4', 'table5]]'
            $schema = 'schema1', 'sche..ma2', 'sche ma3', 'schema4', 'schema5'
            for ($i = 0; $i -lt $input.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $input[$i]
                $result.Parsed | Should Be $true
                $result.Database | Should Be $null
                $result.Schema | Should Be $schema[$i]
                $result.Name | Should Be $table[$i]
            }
        }
    }
    Context "Test three part names" {
        It "Should return correct parts" {
            $input = 'database1.schema1.table1', 'database2..table2', 'database3..[tab..le3]', 'db4.[sche..ma4].table4'
            $table = 'table1', 'table2', 'tab..le3', 'table4'
            $schema = 'schema1', $null, $null, 'sche..ma4'
            $database = 'database1', 'database2', 'database3', 'db4'
            for ($i = 0; $i -lt $input.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $input[$i]
                $result.Parsed | Should Be $true
                $result.Database | Should Be $database[$i]
                $result.Schema | Should Be $schema[$i]
                $result.Name | Should Be $table[$i]
            }
        }
    }
    Context "Test wrong names" {
        It "Should not return parts" {
            $input = 'schema1...table1', 'sche..ma2.table2', 'correct.to.testthetest'
            for ($i = 0; $i -lt $input.Count; $i++) {
                $result = Get-ObjectNameParts -ObjectName $input[$i]
                $result.Parsed | Should Be $false
            }
        }
    }
}
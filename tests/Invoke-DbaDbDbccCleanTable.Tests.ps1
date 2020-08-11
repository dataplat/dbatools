$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Object', 'BatchSize', 'NoInformationalMessages', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolct_example (object_id int, [definition] nvarchar(max),Document varchar(2000));
        INSERT INTO dbo.dbatoolct_example([object_id], [definition], Document) Select [object_id], [definition], REPLICATE('ab', 800) from master.sys.sql_modules;
        ALTER TABLE dbo.dbatoolct_example DROP COLUMN Definition, Document;")
    }
    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.dbatoolct_example")
        } catch {
            $null = 1
        }
    }

    Context "Validate standard output" {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Cmd', 'Output'
        $result = Invoke-DbaDbDbccCleanTable -SqlInstance $script:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -Confirm:$false

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }

        It "returns correct results" {
            $result.Database -eq 'tempdb' | Should Be $true
            $result.Object -eq 'dbo.dbatoolct_example' | Should Be $true
            $result.Output.Substring(0, 25) -eq 'DBCC execution completed.' | Should Be $true
        }
    }

    Context "Validate BatchSize parameter " {
        $result = Invoke-DbaDbDbccCleanTable -SqlInstance $script:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -BatchSize 1000 -Confirm:$false

        It "returns results for table" {
            $result.Cmd -eq "DBCC CLEANTABLE('tempdb', 'dbo.dbatoolct_example', 1000)" | Should Be $true
            $result.Output.Substring(0, 25) -eq 'DBCC execution completed.' | Should Be $true
        }
    }

    Context "Validate NoInformationalMessages parameter " {
        $result = Invoke-DbaDbDbccCleanTable -SqlInstance $script:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -NoInformationalMessages -Confirm:$false

        It "returns results for table" {
            $result.Cmd -eq "DBCC CLEANTABLE('tempdb', 'dbo.dbatoolct_example') WITH NO_INFOMSGS" | Should Be $true
            $result.Output -eq $null | Should Be $true
        }
    }
}
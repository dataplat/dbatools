$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeSystemDBs', 'Table', 'EnableException', 'InputObject'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsscidb_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname -Owner sa
        $tablename = "dbatoolssci_$(Get-Random)"
        $null = Invoke-DbaQuery -SqlInstance $script:instance1 -Database $dbname -Query "Create table $tablename (col1 int)"
    }
    AfterAll {
        $null = Invoke-DbaQuery -SqlInstance $script:instance1 -Database $dbname -Query "drop table $tablename"
        $null = Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }
    Context "Should get the table" {
        It "Gets the table" {
            (Get-DbaDbTable -SqlInstance $script:instance1).Name | Should Contain $tablename
        }
        It "Gets the table when you specify the database" {
            (Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname).Name | Should Contain $tablename
        }
    }
    Context "Should not get the table if database is excluded" {
        It "Doesn't find the table" {
            (Get-DbaDbTable -SqlInstance $script:instance1 -ExcludeDatabase $dbname).Name | Should Not Contain $tablename
        }
    }
}
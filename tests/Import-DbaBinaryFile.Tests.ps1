$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Schema', 'FilePath', 'EnableException', 'Statement', 'NoFileNameColumn', 'BinaryColumn', 'FileNameColumn', 'InputObject', 'Path'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb
        $null = $db.Query("CREATE TABLE [dbo].[BunchOFiles]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
    }
    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.BunchOFiles")
        } catch {
            $null = 1
        }
    }

    It "imports files into table data" {
        $results = Import-DbaBinaryFile -SqlInstance $script:instance2 -Database tempdb -Table BunchOFiles -FilePath $script:appveyorlabrepo\azure\adalsql.msi -WarningAction Continue -ErrorAction Stop -EnableException
        $results.Database | Should -Be "tempdb"
        $results.FilePath | Should -match "adalsql.msi"
    }
    It "imports files into table data from piped" {
        $results = Get-ChildItem -Path $script:appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $script:instance2 -Database tempdb -Table BunchOFiles -WarningAction Continue -ErrorAction Stop -EnableException
        $results.Database | Should -Be @("tempdb", "tempdb")
        Split-Path -Path $results.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
    }

    It "piping from Get-DbaBinaryFileTable works" {
        $results = Get-DbaBinaryFileTable -SqlInstance $script:instance2 -Database tempdb -Table BunchOFiles | Import-DbaBinaryFile -WarningAction Continue -ErrorAction Stop -EnableException -Path  $script:appveyorlabrepo\certificates
        $results.Database | Should -Be @("tempdb", "tempdb")
        Split-Path -Path $results.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
    }
}
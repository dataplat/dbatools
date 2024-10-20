$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Schema', 'FileNameColumn', 'BinaryColumn', 'Path', 'FilePath', 'Query', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeEach {
        $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database tempdb
        $null = $db.Query("CREATE TABLE [dbo].[BunchOFilezz]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
        $null = Import-DbaBinaryFile -SqlInstance $TestConfig.instance2 -Database tempdb -Table BunchOFilezz -FilePath $TestConfig.appveyorlabrepo\azure\adalsql.msi
        $null = Get-ChildItem $TestConfig.appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $TestConfig.instance2 -Database tempdb -Table BunchOFilezz
    }
    AfterEach {
        try {
            $null = $db.Query("DROP TABLE dbo.BunchOFilezz")
            $null = Get-ChildItem -Path C:\temp\exports -File | Remove-Item -Confirm:$false -Force
        } catch {
            $null = 1
        }
    }

    It "exports the table data to file" {
        $results = Export-DbaBinaryFile -SqlInstance $TestConfig.instance2 -Database tempdb -Path C:\temp\exports
        $results.Name.Count | Should -Be 3
        $results.Name | Should -Be @('adalsql.msi', 'localhost.crt', 'localhost.pfx')
    }

    It "exports the table data to file" {
        $results = Get-DbaBinaryFileTable -SqlInstance $TestConfig.instance2 -Database tempdb | Export-DbaBinaryFile -Path C:\temp\exports
        $results.Name.Count | Should -Be 3
        $results.Name | Should -Be @('adalsql.msi', 'localhost.crt', 'localhost.pfx')
    }
}

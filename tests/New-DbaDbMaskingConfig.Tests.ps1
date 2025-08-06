$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Column', 'Path', 'Locale', 'CharacterString', 'SampleCount', 'KnownNameFilePath', 'PatternFilePath', 'ExcludeDefaultKnownName', 'ExcludeDefaultPattern', 'Force', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_maskconfig"
        $sql = "CREATE TABLE [dbo].[people](
                    [fname] [varchar](50) NULL,
                    [lname] [varchar](50) NULL,
                    [dob] [datetime] NULL
                ) ON [PRIMARY]"
        $db = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbname
        $db.Query($sql)
        $sql = "INSERT INTO people (fname, lname, dob) VALUES ('Joe','Schmoe','2/2/2000')
                INSERT INTO people (fname, lname, dob) VALUES ('Jane','Schmee','2/2/1950')"
        $db.Query($sql)

        # bug 6934
        $db.Query("
                CREATE TABLE dbo.DbConfigTest
                (
                    id              SMALLINT      NOT NULL,
                    IPAddress       VARCHAR(100)  NOT NULL,
                    Address         VARCHAR(100)  NOT NULL,
                    StreetAddress   VARCHAR(100)  NOT NULL,
                    Street          VARCHAR(100)  NOT NULL
                );
                INSERT INTO dbo.DbConfigTest (id, IPAddress, Address, StreetAddress, Street)
                VALUES
                (1, '127.0.0.1', '123 Fake Street', '123 Fake Street', '123 Fake Street'),
                (2, '', '123 Fake Street', '123 Fake Street', '123 Fake Street'),
                (3, 'fe80::7df3:7015:89e9:fbed%15', '123 Fake Street', '123 Fake Street', '123 Fake Street')")
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname -Confirm:$false
        $results | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Command works" {

        It "Should output a file with specific content" {
            $results = New-DbaDbMaskingConfig -SqlInstance $TestConfig.instance1 -Database $dbname -Path C:\temp
            $results.Directory.Name | Should -Be temp
            $results.FullName | Should -FileContentMatch $dbname
            $results.FullName | Should -FileContentMatch fname

            Remove-Item -Path $results.FullName
        }

        It "Bug 6934: matching IPAddress, Address, and StreetAddress on known names" {
            $results = New-DbaDbMaskingConfig -SqlInstance $TestConfig.instance1 -Database $dbname -Table DbConfigTest -Path C:\temp
            $jsonOutput = Get-Content $results.FullName | ConvertFrom-Json

            $jsonOutput.Tables.Columns[1].Name | Should -Be "IPAddress"
            $jsonOutput.Tables.Columns[1].MaskingType | Should -Be "Internet"
            $jsonOutput.Tables.Columns[1].SubType | Should -Be "Ip"

            $jsonOutput.Tables.Columns[2].Name | Should -Be "Address"
            $jsonOutput.Tables.Columns[2].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[2].SubType | Should -Be "StreetAddress"

            $jsonOutput.Tables.Columns[3].Name | Should -Be "StreetAddress"
            $jsonOutput.Tables.Columns[3].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[3].SubType | Should -Be "StreetAddress"

            $jsonOutput.Tables.Columns[4].Name | Should -Be "Street"
            $jsonOutput.Tables.Columns[4].MaskingType | Should -Be "Address"
            $jsonOutput.Tables.Columns[4].SubType | Should -Be "StreetAddress"

            Remove-Item -Path $results.FullName
        }
    }
}

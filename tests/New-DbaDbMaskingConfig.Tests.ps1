$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Column', 'Path', 'Locale', 'CharacterString', 'SampleCount', 'KnownNameFilePath', 'PatternFilePath', 'ExcludeDefaultKnownName', 'ExcludeDefaultPattern', 'Force', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
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
        $db = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname
        $db.Query($sql)
        $sql = "INSERT INTO people (fname, lname, dob) VALUES ('Joe','Schmoe','2/2/2000')
                INSERT INTO people (fname, lname, dob) VALUES ('Jane','Schmee','2/2/1950')"
        $db.Query($sql)
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
        $results | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Command works" {

        It "Should output a file with specific content" {
            $results = New-DbaDbMaskingConfig -SqlInstance $script:instance1 -Database $dbname -Path C:\temp
            $results.Directory.Name | Should -Be temp
            $results.FullName | Should -FileContentMatch $dbname
            $results.FullName | Should -FileContentMatch fname
        }
    }
}
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\New-DbaDbMaskingConfig).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Column', 'Path', 'Locale', 'Force', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $db = "dbatoolsci_maskconfig"
        $sql = "CREATE TABLE [dbo].[people](
                    [fname] [varchar](50) NULL,
                    [lname] [varchar](50) NULL,
                    [dob] [datetime] NULL
                ) ON [PRIMARY]
                GO
                INSERT INTO people (fname, lname, dob) VALUES ('Joe','Schmoe','2/2/2000')
                INSERT INTO people (fname, lname, dob) VALUES ('Jane','Schmee','2/2/1950')"
        New-DbaDatabase -SqlInstance $script:instance1 -Name $db
        Invoke-DbaQuery -SqlInstance $script:instance1 -Query $sql -Database $db
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $db -Confirm:$false
        $results | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Command works" {

        It "Should output a file with specific content" {
            $results = New-DbaDbMaskingConfig -SqlInstance $script:instance1 -Database $db -Path C:\temp
            $results.Directory.Name | Should -Be temp
            $results.FullName | Should -FileContentMatch $db
            $results.FullName | Should -FileContentMatch fname
        }
    }
}
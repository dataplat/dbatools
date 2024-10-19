param($ModuleName = 'dbatools')

Describe "Set-DbaDbFileGroup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $db1name = "dbatoolsci_filegroup_test_$random"
        $fileGroup1Name = "FG1"
        $fileGroup2Name = "FG2"
        $fileGroupROName = "FG1RO"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $newDb1 = New-DbaDatabase -SqlInstance $global:instance2 -Name $db1name

        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup1Name")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup2Name")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroupROName")
        $server.Query("ALTER DATABASE $db1name ADD FILE (NAME = test1, FILENAME = '$($server.MasterDBPath)\test1.ndf') TO FILEGROUP $fileGroup1Name")
        $server.Query("ALTER DATABASE $db1name ADD FILE (NAME = testRO, FILENAME = '$($server.MasterDBPath)\testRO.ndf') TO FILEGROUP $fileGroupROName")
    }

    AfterAll {
        $newDb1 | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbFileGroup
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "FileGroup",
                "Default",
                "ReadOnly",
                "AutoGrowAllFiles",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        It "Sets the options for default, readonly, readwrite, autogrow all files, and not autogrow all files" {
            $results = Set-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup1Name -Default -AutoGrowAllFiles -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name
            $results.AutogrowAllFiles | Should -Be $true
            $results.IsDefault | Should -Be $true

            $results = Set-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup1Name -AutoGrowAllFiles:$false -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name
            $results.AutogrowAllFiles | Should -Be $false

            $results = Set-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroupROName -ReadOnly -Confirm:$false
            $results.Name | Should -Be $fileGroupROName
            $results.AutogrowAllFiles | Should -Be $false
            $results.IsDefault | Should -Be $false
            $results.ReadOnly | Should -Be $true

            $results = Set-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup1Name, $fileGroupROName -ReadOnly:$false -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name, $fileGroupROName
            $results.ReadOnly | Should -Be $false, $false
        }

        It "A warning is returned when trying to set the options for a filegroup that doesn't exist" {
            $results = Set-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup invalidFileGroupName -Default -AutoGrowAllFiles -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*Filegroup invalidFileGroupName does not exist in the database $db1name on $($global:instance2)"
        }

        It "A warning is returned when trying to set the options for an empty filegroup" {
            $results = Set-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup2Name -Default -AutoGrowAllFiles -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*Filegroup $fileGroup2Name is empty on $db1name on $($global:instance2). Before the options can be set there must be at least one file in the filegroup."
        }

        It "Sets the filegroup options using a database from a pipeline and a filegroup from a pipeline" {
            $results = $newDb1 | Set-DbaDbFileGroup -FileGroup Primary -Default -Confirm:$false
            $results.Name | Should -Be Primary
            $results.IsDefault | Should -Be $true

            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup1Name | Set-DbaDbFileGroup -Default -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name
            $results.IsDefault | Should -Be $true

            $fg1 = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup $fileGroup1Name
            $results = $fg1, $newDb1 | Set-DbaDbFileGroup -FileGroup Primary -AutoGrowAllFiles -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name, Primary
            $results.AutoGrowAllFiles | Should -Be $true, $true
        }
    }
}

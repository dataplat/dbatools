$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'FileGroupName', 'Default', 'ReadOnly', 'AutoGrowAllFiles', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $db1name = "dbatoolsci_filegroup_test_$random"
        $fileGroup1Name = "FG1"
        $fileGroup2Name = "FG2"
        $fileGroupROName = "FG1RO"

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $newDb1 = New-DbaDatabase -SqlInstance $script:instance2 -Name $db1name

        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup1Name")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroup2Name")
        $server.Query("ALTER DATABASE $db1name ADD FILEGROUP $fileGroupROName")
        $server.Query("ALTER DATABASE $db1name ADD FILE (NAME = test1, FILENAME = '$($server.MasterDBPath)\test1.ndf') TO FILEGROUP $fileGroup1Name")
        $server.Query("ALTER DATABASE $db1name ADD FILE (NAME = testRO, FILENAME = '$($server.MasterDBPath)\testRO.ndf') TO FILEGROUP $fileGroupROName")
    }
    AfterAll {
        $newDb1 | Remove-DbaDatabase -Confirm:$false
    }

    Context "ensure command works" {

        It "Sets the options for default, readonly, and autogrow all files" {
            $results = Set-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName $fileGroup1Name -Default -AutoGrowAllFiles -Confirm:$false
            $results.Name | Should -Be $fileGroup1Name
            $results.AutogrowAllFiles | Should -Be $true
            $results.IsDefault | Should -Be $true

            $results = Set-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName $fileGroupROName -ReadOnly -Confirm:$false
            $results.Name | Should -Be $fileGroupROName
            $results.AutogrowAllFiles | Should -Be $false
            $results.IsDefault | Should -Be $false
            $results.ReadOnly | Should -Be $true
        }

        It "A warning is returned when trying to set the options for a filegroup that doesn't exist" {
            $results = Set-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName invalidFileGroupName -Default -AutoGrowAllFiles -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*Filegroup invalidFileGroupName does not exist in the database $db1name on $($script:instance2)"
        }

        It "A warning is returned when trying to set the options for an empty filegroup" {
            $results = Set-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName $fileGroup2Name -Default -AutoGrowAllFiles -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*Filegroup $fileGroup2Name is empty on $db1name on $($script:instance2). Before the filegroup options can be set there must be at least one file."
        }

        It "Sets the options for a filegroup using a database from a pipeline" {
            $results = $newDb1 | Set-DbaDbFileGroup -FileGroupName Primary -Default -Confirm:$false
            $results.Name | Should -Be Primary
            $results.IsDefault | Should -Be $true
        }
    }
}
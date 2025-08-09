$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'FileGroup', 'FileGroupType', 'InputObject', 'EnableException'
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
        $db2name = "dbatoolsci_filegroup_test2_$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $newDb1 = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db1name
        $newDb2 = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db2name

        $fileStreamStatus = Get-DbaFilestream -SqlInstance $TestConfig.instance2

        if ($fileStreamStatus.InstanceAccessLevel -eq 0) {
            Enable-DbaFilestream -SqlInstance $TestConfig.instance2 -Confirm:$false -Force
            $resetFileStream = $true
        } else {
            $resetFileStream = $false
        }

    }
    AfterAll {
        $newDb1, $newDb2 | Remove-DbaDatabase -Confirm:$false

        if ($resetFileStream) {
            Disable-DbaFilestream -SqlInstance $TestConfig.instance2 -Confirm:$false -Force
        }
    }

    Context "ensure command works" {

        It "Creates a filegroup" {
            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_$random"
            $results.Parent.Name | Should -Be $db1name
            $results.Name | Should -Be "filegroup_$random"
            $results.FileGroupType | Should -Be RowsFileGroup
        }

        It "Check the validation for duplicate filegroup names" {
            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_$random" -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
        }

        It "Creates a filegroup of each FileGroupType" {
            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_rows_$random" -FileGroupType RowsFileGroup
            $results.Name | Should -Be "filegroup_rows_$random"
            $results.FileGroupType | Should -Be RowsFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_filestream_$random" -FileGroupType FileStreamDataFileGroup
            $results.Name | Should -Be "filegroup_filestream_$random"
            $results.FileGroupType | Should -Be FileStreamDataFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_memory_optimized_$random" -FileGroupType MemoryOptimizedDataFileGroup
            $results.Name | Should -Be "filegroup_memory_optimized_$random"
            $results.FileGroupType | Should -Be MemoryOptimizedDataFileGroup

        }

        It "Creates a filegroup using a database from a pipeline" {
            $results = $newDb1 | New-DbaDbFileGroup -FileGroup "filegroup_pipeline_$random"
            $results.Name | Should -Be "filegroup_pipeline_$random"
            $results.Parent.Name | Should -Be $db1name

            $results = $newDb1 | New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db2name -FileGroup "filegroup_pipeline2_$random"
            $results.Name | Should -Be "filegroup_pipeline2_$random", "filegroup_pipeline2_$random"
            $results.Parent.Name | Should -Be $db1name, $db2name
        }
    }
}

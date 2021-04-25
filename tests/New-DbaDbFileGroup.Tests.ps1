$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'FileGroupName', 'FileGroupType', 'Default', 'ReadOnly', 'AutoGrowAllFiles', 'InputObject', 'EnableException'
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

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $newDb1 = New-DbaDatabase -SqlInstance $script:instance2 -Name $db1name
        $newDb2 = New-DbaDatabase -SqlInstance $script:instance2 -Name $db2name

        $fileStreamStatus = Get-DbaFilestream -SqlInstance $script:instance2

        if ($fileStreamStatus.InstanceAccessLevel -eq 0) {
            Enable-DbaFilestream -SqlInstance $script:instance2 -Confirm:$false -Force
        }
    }
    AfterAll {
        $newDb1, $newDb2 | Remove-DbaDatabase -Confirm:$false
        Disable-DbaFilestream -SqlInstance $script:instance2 -Confirm:$false -Force
    }

    Context "ensure command works" {

        It "Creates a filegroup with the defaults" {
            $results = New-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName "filegroup_$random"
            $results.Parent.Name | Should -Be $db1name
            $results.Name | Should -Be "filegroup_$random"
            $results.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::RowsFileGroup
            $results.AutogrowAllFiles = $false
            $results.IsDefault = $false
            $results.ReadOnly = $false

            # check the validation for duplicate filegroup names
            $results = New-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName "filegroup_$random"
            $results | Should -BeNullOrEmpty
        }

        It "Creates a filegroup of each FileGroupType" {
            $results = New-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName "filegroup_rows_$random" -FileGroupType RowsFileGroup
            $results.Name | Should -Be "filegroup_rows_$random"
            $results.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::RowsFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName "filegroup_filestream_$random" -FileGroupType FileStreamDataFileGroup
            $results.Name | Should -Be "filegroup_filestream_$random"
            $results.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::FileStreamDataFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName "filegroup_memory_optimized_$random" -FileGroupType MemoryOptimizedDataFileGroup
            $results.Name | Should -Be "filegroup_memory_optimized_$random"
            $results.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::MemoryOptimizedDataFileGroup

        }

        It "Creates a filegroup with default, readonly, and autogrow" {
            $results = New-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName "filegroup_options_$random" -Default -AutoGrowAllFiles
            $results.Name | Should -Be "filegroup_options_$random"
            $results.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::RowsFileGroup
            $results.AutogrowAllFiles = $true
            $results.IsDefault = $true

            $results = New-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db1name -FileGroupName "filegroup_options_RO_$random" -ReadOnly
            $results.Name | Should -Be "filegroup_options_RO_$random"
            $results.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::RowsFileGroup
            $results.AutogrowAllFiles = $false
            $results.IsDefault = $false
            $results.ReadOnly = $true
        }

        It "Creates a filegroup using a database from a pipeline" {
            $results = $newDb1 | New-DbaDbFileGroup -FileGroupName "filegroup_pipeline_$random"
            $results.Name | Should -Be "filegroup_pipeline_$random"

            $results = $newDb1 | New-DbaDbFileGroup -SqlInstance $script:instance2 -Database $db2name -FileGroupName "filegroup_pipeline2_$random"
            $results.Name | Should -Be "filegroup_pipeline2_$random", "filegroup_pipeline2_$random"
            $results.Parent.Name | Should -Be $db1name, $db2name
        }
    }
}
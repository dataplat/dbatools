param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbShrink Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbShrink
        }

        It "has the required parameter: <_>" -ForEach $params {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "AllUserDatabases",
                "PercentFreeSpace",
                "ShrinkMethod",
                "FileType",
                "StepSize",
                "StatementTimeout",
                "ExcludeIndexStats",
                "ExcludeUpdateUsage",
                "EnableException"
            )
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Invoke-DbaDbShrink Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $defaultPath = $server | Get-DbaDefaultPath
    }

    Context "Verifying Database is shrunk" {
        BeforeEach {
            # Create Database with small size and grow it
            $db = New-Object Microsoft.SqlServer.Management.SMO.Database($server, "dbatoolsci_shrinktest")

            $primaryFileGroup = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($db, "PRIMARY")
            $db.FileGroups.Add($primaryFileGroup)
            $primaryFile = New-Object Microsoft.SqlServer.Management.SMO.DataFile($primaryFileGroup, $db.Name)
            $primaryFile.FileName = "$($defaultPath.Data)\$($db.Name).mdf"
            $primaryFile.Size = 8 * 1024
            $primaryFile.Growth = 8 * 1024
            $primaryFile.GrowthType = "KB"
            $primaryFileGroup.Files.Add($primaryFile)

            $logFile = New-Object Microsoft.SqlServer.Management.SMO.LogFile($db, "$($db.Name)_log")
            $logFile.FileName = "$($defaultPath.Log)\$($db.Name)_log.ldf"
            $logFile.Size = 8 * 1024
            $logFile.Growth = 8 * 1024
            $logFile.GrowthType = "KB"
            $db.LogFiles.Add($logFile)

            $db.Create()

            # grow the files
            $server.Query("
            ALTER DATABASE [$($db.name)] MODIFY FILE ( NAME = N'$($db.name)', SIZE = 16384KB )
            ALTER DATABASE [$($db.name)] MODIFY FILE ( NAME = N'$($db.name)_log', SIZE = 16384KB )")

            # Save the current file sizes
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $oldLogSize = $db.LogFiles[0].Size
            $oldDataSize = $db.FileGroups[0].Files[0].Size
            $db.Checkpoint()
        }

        AfterEach {
            $db | Remove-DbaDatabase -Confirm:$false
        }

        It "Shrinks just the log file when FileType is Log" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Log
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be "$($db.Name)_log"
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -Be $oldDataSize
            $db.LogFiles[0].Size | Should -BeLessThan $oldLogSize
        }

        It "Shrinks just the data file(s) when FileType is Data" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Data
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }

        It "Shrinks the entire database when FileType is All" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType All
            $result.Database | Should -Be $db.Name, $db.Name
            $result.File | Should -Be "$($db.Name)_log", $db.Name
            $result.Success | Should -Be $true, $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.LogFiles[0].Size | Should -BeLessThan $oldLogSize
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
        }

        It "Shrinks just the data file(s) when FileType is Data and uses the StepSize" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Data -StepSize 2MB
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }
    }
}

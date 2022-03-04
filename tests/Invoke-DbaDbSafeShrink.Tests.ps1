$global:CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$global:CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            # https://pester-docs.netlify.app/docs/migrations/breaking-changes-in-v5#:~:text=Variables%20defined%20during%20Discovery
            [object[]]$params = (Get-Command $global:CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'AllUserDatabases', 'StatementTimeout', 'MinimumFreeSpace', 'EnableException'

            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
            $ref = ($knownParameters | Where-Object { $_ })
            $compare = (Compare-Object -ReferenceObject $ref -DifferenceObject $params).Count 
            $compare | Should -Be 0
        }
    }
}

Describe "$global:CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying Database is shrunk" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $defaultPath = $server | Get-DbaDefaultPath
        }
        BeforeEach {
            # Create Database with small size and grow it
            $db = New-Object Microsoft.SqlServer.Management.SMO.Database($server, "dbatoolsci_safeshrinktest")

            $primaryFileGroup = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($db, "PRIMARY")
            $db.FileGroups.Add($primaryFileGroup)
            $primaryFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile($primaryFileGroup, $db.Name)
            $primaryFile.FileName = "$($defaultPath.Data)\$($db.Name).mdf"
            $primaryFile.Size = 8 * 1024
            $primaryFile.Growth = 256
            $primaryFile.GrowthType = "KB"
            $primaryFileGroup.Files.Add($primaryFile)

            $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile($db, "$($db.Name)_log")
            $logFile.FileName = "$($defaultPath.Log)\$($db.Name)_log.ldf"
            $logFile.Size = 8 * 1024
            $logFile.Growth = 256
            $logFile.GrowthType = "KB"
            $db.LogFiles.Add($logFile)

            $db.Create()

            # create a table as the shrink only works when there is a table
            $server.Query("
                IF OBJECT_ID('dbo.foo', 'U') IS NULL BEGIN
	                CREATE TABLE dbo.foo (
		                [id] INT NOT NULL IDENTITY,
		                [data] sysname NOT NULL,
		                CONSTRAINT [PK_foo_id] PRIMARY KEY CLUSTERED (id),
	                ) ON [PRIMARY];
                END", $db.Name)
                
            $server.Query("
                INSERT INTO dbo.[foo] (
                    [data]
                )
                SELECT name 
                FROM master.dbo.[spt_values] AS [sv]
                WHERE [sv].[name] IS NOT NULL", $db.Name)

            # grow the files
            $server.Query("
            ALTER DATABASE [$($db.name)] MODIFY FILE ( NAME = N'$($db.name)', SIZE = 25MB )
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

        It "Shrinks just the data file(s)" {
            $result = Invoke-DbaDbSafeShrink $server -Database $db.Name
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Refresh()
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }

        It "Does not shrink the database when the MinimumFreeSpace does not exceed the current free space" {
            $result = Invoke-DbaDbSafeShrink $server -Database $db.Name -MinimumFreeSpace 1GB
            $result | Should -BeNullOrEmpty
        }
    }
}
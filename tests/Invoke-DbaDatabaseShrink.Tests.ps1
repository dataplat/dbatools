$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying Database is shrunk" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1 
        }
        BeforeEach {
            # Create Database with small size and grow it
            $db = New-Object Microsoft.SqlServer.Management.SMO.Database($server, "dbatoolsci_shrinktest")
            
            $primaryFileGroup = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($db, "PRIMARY")
            $db.FileGroups.Add($primaryFileGroup)
            $primaryFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile($primaryFileGroup, $db.Name)
            $primaryFile.FileName = "$($server.DefaultFile)\$($db.Name).mdf"
            $primaryFile.Size = 8 * 1024
            $primaryFile.Growth = 8 * 1024
            $primaryFile.GrowthType = "KB"
            $primaryFileGroup.Files.Add($primaryFile)

            $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile($db, "$($db.Name)_log")
            $logFile.FileName = "$($server.DefaultLog)\$($db.Name)_log.ldf"
            $logFile.Size = 8 * 1024
            $logFile.Growth = 8 * 1024
            $logFile.GrowthType = "KB"
            $db.LogFiles.Add($logFile)
            
            $db.Create()

            # Execute a bunch of inserts in a transaction to grow the data and log files
            $conn = $server.ConnectionContext
            $conn.ExecuteNonQuery("use $($db.Name);")
            $conn.BeginTransaction();
            $conn.ExecuteNonQuery("create table dbatoolsci_test1 (col1 char(8000));")
            1..1000 | foreach {
                $conn.ExecuteNonQuery("insert into dbatoolsci_test1 values('data');")
            }
            $conn.ExecuteNonQuery("drop table dbatoolsci_test1;")
            $conn.CommitTransaction();

            # Save the current file sizes
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $oldLogSize = $db.LogFiles[0].Size
            $oldDataSize = $db.FileGroups[0].Files[0].Size
        }
        AfterEach {
            $db | Remove-DbaDatabase -Confirm:$false
        }

        It "Shrinks just the log file when Type is Log" {
            Invoke-DbaDatabaseShrink $server -Database $db.Name -LogsOnly -ShrinkMethod TruncateOnly
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should Be $oldDataSize
            $db.LogFiles[0].Size | Should BeLessThan $oldLogSize
        }

        It "Shrinks the entire database when Type is All" {
            Invoke-DbaDatabaseShrink $server -Database $db.Name
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.LogFiles[0].Size | Should BeLessThan $oldLogSize
            $db.FileGroups[0].Files[0].Size | Should BeLessThan $oldDataSize
        }
    }
}
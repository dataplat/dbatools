# not added into module - just wanted to get this down whilst it was still in my head 
# needs proper help and proper parameters
# needs try catch
# needs shouldprocess added
# Ready for more comments and suggestions
# Need to validate for monthyear or year but not have both?

function Get-DbaBackupThroughput
{
param (
[object]$Server,
[object]$database,
[ValidatePattern(“(?# SHOULD BE 2 digits hyphen 4 digits)\d{2}-\d{4}”)]
[string]$MonthYear,
[ValidatePattern(“(?# SHOULD BE 4)\d{4}”)]
[string]$Year,
## Shows the results per db otherwise it shows a total
[switch]$EveryDB)
    # Load SMO extension
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null;
    # function to generate and show the output
    function Show-Output
    {
param([object]$a)

$Throughput =  $a|Measure-Object -Property 'Throughput' -Sum -Average -Maximum -Minimum
$BackupDate = $a|Measure-Object -Property 'BackupFinishDate' -Maximum -Minimum

$Return = [pscustomobject]@{Instance = $Server;
Database = $db
MinDate = $BackupDate.Minimum;
MaxDate = $BackupDate.Maximum; 
MaxThroughput = $Throughput.Maximum;
MinThroughput = $Throughput.Minimum;
AvgThroughput = $Throughput.Average }

$MaxDate = $Return.MaxDate
$MinDate = $Return.MinDate
Write-Output "$Server has managed a backup throughput in Mb/sec between $MinDate and $MaxDate of :- "
Return $Return
}
    # Backp Throughput calc from Brent Ozar blog 
    $TPexp = @{Name='Throughput';Expression = {($_.BackupSize/($_.BackupFinishDate - $_.BackupStartDate).totalseconds)/1048576 }}
    
    ## Probably should take an array of servers?
    $srv = New-Object Microsoft.SqlServer.Management.Smo.Server $Server
    $Results = @()
    ## set the value here so that the filters wirk later 
    if($MonthYear)
    {
[int]$Mnth,[int]$Yr = $MonthYear.Split('-')
}
    else
    {
$mnth = '*'
$yr = '*'
}
    foreach($db in $srv.Databases|Where-Object{$_.Name -ne 'tempdb'})
    {
        if($database)
        {
        if($db.name -eq $database)
        {
            # filters for Fulland Diff Backups
            $backups = $db.EnumBackupSets()|Where-Object{$_.BackupSetType -ne 3 -and (($_.BackupFinishDate - $_.BackupStartDate).totalseconds -gt 1)} |Select DatabaseName,Name,BackupStartDate,BackupFinishDate,BackupSize,BackupSetType 
            if($backups.Throughput -gt 0)
            {
                $Results += $backups
            }
            else
            {
                Write-Warning "No results to show for $database maybe the time was 0 seconds"
            }
        }
    }
        elseif($EveryDB)
        {
        $dbname = $db.name
        $backups = $db.EnumBackupSets()| Where-Object {($_.BackupFinishDate).Month -like $Mnth -and ($_.BackupFinishDate).Year -like $Yr}| Select $TPexp, DatabaseName,Name,BackupStartDate,BackupFinishDate,BackupSize,BackupSetType 
        if($backups.Throughput -gt 0)
        {
            $db =$backups[0].DatabaseName
            Show-Output $backups
        }
        else
        {
            Write-Warning "No results to show for $dbname maybe the time was 0 seconds"
        }
    }
        else
        {
    $dbname = $db.name
    $backups =  $db.EnumBackupSets()| Where-Object {($_.BackupFinishDate).Month -like $Mnth -and ($_.BackupFinishDate).Year -like $Yr}| Select $TPexp, DatabaseName,Name,BackupStartDate,BackupFinishDate,BackupSize,BackupSetType 
        if($backups.Throughput -gt 0)
            {
                $Results += $backups
            }
            else
            {
                Write-Warning "No results to show for $dbname maybe the time was 0 seconds"
            }
    }
    }
    if($results)
    {
        $a = $Results| Where-Object {($_.BackupFinishDate).Month -like $Mnth -and ($_.BackupFinishDate).Year -like $Yr}| Select $TPexp, DatabaseName,Name,BackupStartDate,BackupFinishDate,BackupSize,BackupSetType 
        if($database)
        {
        $db =$a[0].DatabaseName
        }
        else
        {
        $db = 'All'
        }
        
        Show-Output $a
    }
}
 
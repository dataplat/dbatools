function Restore-DbaSystemDatabase
{
    [CmdletBinding(SupportsShouldProcess=$true)]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[PSCredential]$Credential,
        [PSCredential]$SqlCredential,
        [String[]]$BackupPath,
        [DateTime]$RestorePoint,
        [switch]$master,
        [Switch]$model,
        [Switch]$msdb
	)

    $FunctionName =(Get-PSCallstack)[0].Command
$CurrentStartup = Get-DbaStartupParameter -SqlServer $SqlServer
if ($master)
{
    Write-Verbose "$FunctionName - Restoring Master, setting single user"
    Set-DbaStartupParameter -SqlServer $SqlServer -SingleUser
    Stop-DbaService -SqlServer $SqlServer
    Start-DbaService -SqlServer $SqlServer
    Write-Verbose "$FunctionName - Beginning Restore"
    Restore-DbaDatabase -SqlServer $SqlServer -Path $BackupPath -WithReplace -DatabaseFilter master
}
if ($model -or $msdb)
{
    $filter = @()
    if ($model)
    {
        Write-Verbose "$FunctionName - Restoring Model, setting filter"
        $filter += 'model'
    }
    if ($msdb)
    {
        Write-Verbose "$FunctionName - Restoring msdb, setting Filter"
        $filter += 'msdb'
    }
    Set-DbaStartupParameter -SqlServer $SqlServer -SingleUser:$false
    Stop-DbaService -SqlServer $SqlServer
    Start-DbaService -SqlServer $SqlServer
    while ((Get-DbaService -SqlServer $SqlServer -service SqlServer).ServiceState -ne 'running')
    {
        Start-Sleep -seconds 15
    }
    Write-Verbose "Starting restore of $($filter -join ',')"
    Restore-DbaDatabase -SqlServer $SqlServer -Path $BackupPath  -WithReplace -DatabaseFilter $filter
}
Set-DbaStartupParameter -SqlServer $SqlServer -StartUpConfig $CurrentStartup 
Stop-DbaService -SqlServer $SqlServer -Service SqlServer
Start-Sleep -seconds 30
Start-DbaService -SqlServer $SqlServer -service SqlServer
}
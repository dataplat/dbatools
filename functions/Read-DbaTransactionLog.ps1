function Read-DbaTransactionLog {
    <#
.SYNOPSIS
Reads the live Transaction log from specified SQL Server Database

.DESCRIPTION
Using the fn_dblog function, the live transaction log is read and returned as a PowerShell object

This function returns the whole of the log. The information is presented in the format that the logging subsystem uses.

A soft limit of 0.5GB of log as been implemented. This is based on testing. This limit can be overridden
at the users request, but please be aware that this may have an impact on your target databases and on the
system running this function

.PARAMETER SqlInstance
A SQL Server instance to connect to

.PARAMETER SqlCredential
A credential to use to connect to the SQL Instance rather than using Windows Authentication

.PARAMETER Database
Database to read the transaction log of

.PARAMETER IgnoreLimit
Switch to indicate that you wish to bypass the recommended limits of the function

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Databases, Logs
Author: Stuart Moore (@napalmgram), stuart-moore.com

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.EXAMPLE
$Log = Read-DbaTransactionLog -SqlInstance sql2016 -Database MyDatabase

Will read the contents of the transaction log of MyDatabase on SQL Server Instance sql2016 into the local PowerShell object $Log

.EXAMPLE
$Log = Read-DbaTransactionLog -SqlInstance sql2016 -Database MyDatabase -IgnoreLimit

Will read the contents of the transaction log of MyDatabase on SQL Server Instance sql2016 into the local PowerShell object $Log, ignoring the recommnedation of not returning more that 0.5GB of log

#>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [parameter(Position = 0, Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory = $true)]
        [object]$Database,
        [Switch]$IgnoreLimit,
        [Alias('Silent')]
        [switch]$EnableException
    )

    try {
        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    }
    catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        return
    }

    if (-not $server.databases[$Database]) {
        Stop-Function -Message "$Database does not exist"
        return
    }

    if ($server.databases[$Database].Status -ne 'Normal') {
        Stop-Function -Message "$Database is not in a normal State, command will not run."
        return
    }

    if ($IgnoreLimit) {
        Write-Message -Level Verbose -Message "Please be aware that ignoring the recommended limits may impact on the performance of the SQL Server database and the calling system"
    }
    else {
        #Warn if more than 0.5GB of live log. Dodgy conversion as SMO returns the value in an unhelpful format :(
        $SqlSizeCheck = "select
                                sum(FileProperty(sf.name,'spaceused')*8/1024) as 'SizeMb'
                                from sys.sysfiles sf
                                where CONVERT(INT,sf.status & 0x40) / 64=1"
        $TransLogSize = $server.Query($SqlSizeCheck, $Database)
        if ($TransLogSize.SizeMb -ge 500) {
            Stop-Function -Message "$Database has more than 0.5 Gb of live log data, returning this may have an impact on the database and the calling system. If you wish to proceed please rerun with the -IgnoreLimit switch"
            return
        }
    }

    $sql = "select * from fn_dblog(NULL,NULL)"
    Write-Message -Level Debug -Message $sql
    Write-Message -Level Verbose -Message "Starting Log retrieval"
    $server.Query($sql, $Database)

}

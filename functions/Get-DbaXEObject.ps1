function Get-DbaXEObject {
    <#
        .SYNOPSIS
            Gets a list of trace(s) from specified SQL Server instance(s).

        .DESCRIPTION
            This function returns a list of Traces on the specified SQL Server instance(s) and identifies the default Trace File

        .PARAMETER SqlInstance
            Target SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Type
            Used to specify the type. Valid types include:

                Action
                Event
                Map
                Message
                PredicateComparator
                PredicateSource
                Target
                Type

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .EXAMPLE
            Get-DbaXEObject -SqlInstance sql2016

            Lists all the XE Objects on the sql2016 SQL Server.

        .EXAMPLE
            Get-DbaXEObject -SqlInstance sql2017 -Type Action, Event

            Lists all the XE Objects of type Action and Event on the sql2017 SQL Server.

    #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("Type", "Event", "Target", "Action", "Map", "Message", "PredicateComparator", "PredicateSource")]
        [string[]]$Type,
        [switch]$EnableException
    )
    begin {
        if ($Type) {
            $join = $Type -join "','"
            $where = "AND o.object_type in ('$join')"
            $where.Replace("PredicateComparator", "pred_compare")
            $where.Replace("PredicateSource", "pred_source")
        }
        $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
                ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                SERVERPROPERTY('ServerName') AS SqlInstance,
                p.name AS PackageName,
                ObjectType =
                      CASE o.object_type
                         WHEN 'type' THEN 'Type'
                         WHEN 'event' THEN 'Event'
                         WHEN 'target' THEN 'Target'
                         WHEN 'pred_compare' THEN 'PredicateComparator'
                         WHEN 'pred_source' THEN 'PredicateSource'
                         WHEN 'action' THEN 'Action'
                         WHEN 'map' THEN 'Map'
                         WHEN 'message' THEN 'Message'
                         ELSE o.object_type
                      END,
                o.object_type as ObjectTypeRaw,
                o.name AS TargetName,
                o.description as Description
                FROM sys.dm_xe_packages AS p
                JOIN sys.dm_xe_objects AS o ON p.guid = o.package_guid
                WHERE (p.capabilities IS NULL OR p.capabilities & 1 = 0)
                $where
                AND (o.capabilities IS NULL OR o.capabilities & 1 = 0)
                ORDER BY o.object_type
                "
    }
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                return
            }

            try {
                $server.Query($sql) | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, ObjectTypeRaw
            }
            catch {
                Stop-Function -Message "Issue collecting trace data on $server." -Target $server -ErrorRecord $_
            }
        }
    }
}
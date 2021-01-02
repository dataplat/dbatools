function Get-DbaXEObject {
    <#
    .SYNOPSIS
        Gets a list of extended events objects exposed by event packages from specified SQL Server instance(s).

    .DESCRIPTION
        This function returns a list of extended events objects exposed by event packages from specified SQL Server instance(s).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaXEObject

    .EXAMPLE
        PS C:\> Get-DbaXEObject -SqlInstance sql2016

        Lists all the XE Objects on the sql2016 SQL Server.

    .EXAMPLE
        PS C:\> Get-DbaXEObject -SqlInstance sql2017 -Type Action, Event

        Lists all the XE Objects of type Action and Event on the sql2017 SQL Server.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
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
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                return
            }

            try {
                $server.Query($sql) | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, ObjectTypeRaw
            } catch {
                Stop-Function -Message "Issue collecting trace data on $server." -Target $server -ErrorRecord $_
            }
        }
    }
}